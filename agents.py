"""
crewai_sql_pipeline.py

Production-grade NL→SQL pipeline using CrewAI (multi-agent orchestration) + LangChain:

- Planner (NL→SQL via LangChain) → Guardian (read-only & privacy guard) → Executor (SQLAlchemy/pyodbc)
  → Analyst (concise insights)
- Robust safety: read-only enforcement, SELECT * ban, alias-aware user_id filters on private tables,
  configurable row caps, CTE/comment-safe read-only detection.
- Deterministic, stepwise orchestration: one mini-crew per step for reliability in production.
- Structured rows (list[dict]) from the DB for accurate downstream analysis.

Requirements
------------
pip install -U crewai crewai-tools langchain langchain-openai langchain-community sqlalchemy pyodbc pydantic python-dotenv

Environment
-----------
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-4o-mini            # optional (defaults to gpt-4o-mini)
SQL_DEFAULT_CAP=500                 # optional
SQL_MAX_CAP=5000                    # optional
DEMO_USER_ID=138                    # optional
"""

from __future__ import annotations

import os
import re
import json
import logging
import urllib.parse
from typing import List, Dict, Any, Optional

from pydantic import BaseModel, Field, ValidationError

from crewai import Agent, Task, Crew, Process
from crewai.tools import BaseTool

from langchain_openai import ChatOpenAI
from langchain.chains import create_sql_query_chain
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_community.utilities import SQLDatabase

from sqlalchemy import text
from sqlalchemy.engine import Engine, Result

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("crewai_sql_pipeline")

# -----------------------------------------------------------------------------
# DB connection (SQL Server / ODBC)
# -----------------------------------------------------------------------------
def mssql_uri(
    driver: str = "ODBC Driver 17 for SQL Server",
    server: str = r"localhost\SQLExpress",
    database: str = "ZANZA",
    trusted: bool = True,
) -> str:
    """
    Build a SQLAlchemy ODBC connection URI for SQL Server.
    Mirrors the settings used in your existing codebase.
    """
    odbc = (
        f"Driver={{{driver}}};"
        f"Server={server};"
        f"Database={database};"
        f"Trusted_Connection={'Yes' if trusted else 'No'};"
        f"TrustServerCertificate=Yes;"
    )
    return "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(odbc)

DB_URI = mssql_uri()
# A few sample rows per table are injected into the LLM prompt to reduce hallucinations
db = SQLDatabase.from_uri(DB_URI, sample_rows_in_table_info=2)

# Attempt to access the underlying SQLAlchemy engine (version-dependent attr)
ENGINE: Optional[Engine] = getattr(db, "engine", None) or getattr(db, "_engine", None)

# -----------------------------------------------------------------------------
# Safety / Privacy
# -----------------------------------------------------------------------------
DEFAULT_CAP = int(os.getenv("SQL_DEFAULT_CAP", "500"))
MAX_CAP = int(os.getenv("SQL_MAX_CAP", "5000"))

# Per-user tables that MUST be constrained by user_id
PRIVATE_TABLES = {"user_preferences", "user_metrics"}

# Read-only and forbidden statements (handles comments, CTEs)
FORBIDDEN_SQL = re.compile(
    r"\b(UPDATE|INSERT|DELETE|MERGE|EXEC|EXECUTE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b",
    re.IGNORECASE,
)
READONLY_HEAD = re.compile(
    r"^\s*(?:--.*?$|/\*.*?\*/\s*)*(?:WITH\b.*?\bSELECT\b|SELECT\b)",
    re.IGNORECASE | re.DOTALL | re.MULTILINE,
)
STAR_PAT = re.compile(r"\bSELECT\s+\*", re.IGNORECASE)

# Alias finder: FROM tbl AS t  |  JOIN tbl t
ALIAS_PAT = re.compile(r"\b(?:FROM|JOIN)\s+([a-zA-Z0-9_]+)(?:\s+AS)?\s+([a-zA-Z0-9_]+)", re.IGNORECASE)

def is_read_only(sql: str) -> bool:
    return READONLY_HEAD.search(sql or "") is not None and FORBIDDEN_SQL.search(sql or "") is None

def has_select_star(sql: str) -> bool:
    return STAR_PAT.search(sql or "") is not None

def ref_tables(sql: str, known: List[str]) -> List[str]:
    L = (sql or "").lower()
    return sorted({t for t in known if re.search(rf"\b{re.escape(t)}\b", L)})

def alias_map(sql: str) -> Dict[str, List[str]]:
    """
    Map physical table -> list of aliases used in the query.
    {"user_metrics": ["um"], "user_preferences": ["up"]}
    """
    mapping: Dict[str, List[str]] = {}
    for tbl, alias in ALIAS_PAT.findall(sql or ""):
        tbl_l, alias_l = tbl.lower(), alias.lower()
        mapping.setdefault(tbl_l, []).append(alias_l)
    return mapping

def ensure_user_filter(sql: str, tables: List[str], user_id: int) -> str:
    """
    Inject WHERE predicates that scope ALL private tables to the current user_id.
    This may turn LEFT JOINs into effectively inner behavior; preferred to prevent leakage.
    """
    priv_used = [t for t in tables if t in PRIVATE_TABLES]
    if not priv_used:
        return sql

    L = (sql or "").lower()
    # Heuristic: if any user_id predicate exists, accept it
    if re.search(r"\buser_?id\s*=", L):
        return sql

    amap = alias_map(sql)
    preds: List[str] = []
    for t in priv_used:
        aliases = amap.get(t, [])
        if aliases:
            preds.extend([f"{a}.user_id = {int(user_id)}" for a in aliases])
        else:
            preds.append(f"{t}.user_id = {int(user_id)}")

    # AND across all private tables
    clause = "(" + " AND ".join(preds) + ")"

    if re.search(r"\bWHERE\b", sql, re.IGNORECASE):
        return re.sub(r"\bWHERE\b", f"WHERE {clause} AND", sql, count=1, flags=re.IGNORECASE)

    # Insert WHERE before grouping/ordering or append at end
    insert_pt = re.search(r"\b(GROUP BY|ORDER BY|HAVING|OPTION|FOR JSON|FOR XML)\b", sql, re.IGNORECASE)
    if insert_pt:
        i = insert_pt.start()
        return sql[:i] + f" WHERE {clause} " + sql[i:]
    return sql.rstrip().rstrip(";") + f" WHERE {clause};"

def cap_rows(sql: str, requested: Optional[int] = None) -> str:
    """
    Add TOP N for simple SELECTs. Respect existing TOP/OFFSET.
    For CTE-heavy queries, prefer to have the validator add a limit with ORDER BY.
    """
    cap = min(int(requested or DEFAULT_CAP), MAX_CAP)
    # Respect existing TOP or OFFSET/FETCH
    if re.search(r"\bSELECT\s+TOP\s+\d+", sql, re.IGNORECASE) or re.search(r"\bOFFSET\s+\d+\s+ROWS", sql, re.IGNORECASE):
        return sql

    # If starts with WITH CTE, avoid naive injection
    if re.match(r"^\s*(?:--.*?$|/\*.*?\*/\s*)*WITH\b", sql, re.IGNORECASE | re.DOTALL | re.MULTILINE):
        return sql  # rely on validator prompt to add paging

    # Inject after SELECT or SELECT DISTINCT
    sql = re.sub(r"^\s*SELECT\s+DISTINCT\s+", f"SELECT DISTINCT TOP {cap} ", sql, count=1, flags=re.IGNORECASE)
    sql = re.sub(r"^\s*SELECT\s+", f"SELECT TOP {cap} ", sql, count=1, flags=re.IGNORECASE)
    return sql

def safe_sql_transform(sql: str, user_id: int, requested_limit: Optional[int] = None) -> str:
    """
    Apply hard safety constraints and privacy scoping.
    """
    if not sql or not is_read_only(sql):
        raise ValueError("Refusing non-read-only SQL. Only SELECT/CTE queries are allowed.")
    if has_select_star(sql):
        raise ValueError("Refusing SELECT *. Request explicit columns.")

    known_tables = [t.lower() for t in db.get_usable_table_names()]
    tables_in_sql = ref_tables(sql, known_tables)
    if not tables_in_sql:
        logger.warning("No known tables referenced; query may fail.")

    sql = ensure_user_filter(sql, tables_in_sql, user_id)
    sql = cap_rows(sql, requested_limit)
    return sql

# -----------------------------------------------------------------------------
# LangChain: NL→SQL + Validation
# -----------------------------------------------------------------------------
llm = ChatOpenAI(
    model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
    temperature=0,
    timeout=60,
    max_retries=2,
)

# Base NL→SQL: uses the live schema supplied by SQLDatabase
sql_gen_chain = create_sql_query_chain(llm, db)

# Validator: fix common issues, enforce explicit columns & pagination guidance
_validator_prompt = ChatPromptTemplate.from_messages(
    [
        (
            "system",
            """You are a meticulous SQL Server (T-SQL) reviewer.
- Avoid SELECT *; use explicit columns that exist.
- If result can be large, add ORDER BY and TOP {cap} or OFFSET/FETCH.
- Check NOT IN + NULL, UNION vs UNION ALL, BETWEEN edges, join keys, casts/types.
- Return ONLY the final SQL (no prose).""",
        ),
        ("human", "{query}"),
    ]
).partial(cap=str(DEFAULT_CAP))

validation_chain = _validator_prompt | llm | StrOutputParser()

def generate_and_validate_sql(question: str) -> str:
    raw_sql = sql_gen_chain.invoke({"question": question})
    return validation_chain.invoke({"query": raw_sql})

# -----------------------------------------------------------------------------
# CrewAI Tools
# -----------------------------------------------------------------------------
class NL2SQLInput(BaseModel):
    question: str = Field(..., description="User's natural-language question")

class NL2SQLTool(BaseTool):
    name: str = "nl2sql_tool"
    description: str = "Generate a read-only SQL Server SELECT for the given question."
    args_schema = NL2SQLInput

    def _run(self, question: str) -> str:
        return generate_and_validate_sql(question)

class GuardSQLInput(BaseModel):
    sql: str = Field(..., description="Candidate SQL query")
    user_id: int = Field(..., description="Current user id for privacy filtering")
    limit: Optional[int] = Field(None, description="Requested row cap")

class GuardSQLTool(BaseTool):
    name: str = "guard_sql_tool"
    description: str = "Enforce read-only, ban SELECT *, inject user_id filter on private tables, cap rows."
    args_schema = GuardSQLInput

    def _run(self, sql: str, user_id: int, limit: Optional[int] = None) -> str:
        return safe_sql_transform(sql, user_id=user_id, requested_limit=limit)

class ExecSQLInput(BaseModel):
    sql: str = Field(..., description="Final safe SQL to execute")

class ExecSQLTool(BaseTool):
    name: str = "exec_sql_tool"
    description: str = "Execute SQL on SQL Server and return rows as list[dict]."
    args_schema = ExecSQLInput

    def _run(self, sql: str) -> Any:
        if ENGINE is None:
            # Fallback to string repr (LangChain's db.run)
            logger.warning("SQLAlchemy engine unavailable on SQLDatabase; using db.run fallback.")
            return db.run(sql)
        with ENGINE.begin() as conn:
            result: Result = conn.execute(text(sql))
            # Convert to list of dicts for robust downstream analysis
            return [dict(row._mapping) for row in result]

# -----------------------------------------------------------------------------
# CrewAI Agents
# -----------------------------------------------------------------------------
planner = Agent(
    role="SQL Planner",
    goal="Turn user questions into correct SQL Server SELECT queries using the live schema.",
    backstory="A T-SQL expert who never guesses column names and prefers minimal, correct queries.",
    tools=[NL2SQLTool()],
    allow_delegation=False,
)

guardian = Agent(
    role="Privacy & Safety Officer",
    goal="Ensure queries are read-only, user-scoped, explicit-column, and row-capped.",
    backstory="Security-first engineer specializing in data governance and least-privilege access.",
    tools=[GuardSQLTool()],
    allow_delegation=False,
)

executor = Agent(
    role="SQL Executor",
    goal="Run safe SQL against the database and return structured rows.",
    backstory="DBA who executes audited queries and returns stable, typed outputs.",
    tools=[ExecSQLTool()],
    allow_delegation=False,
)

analyst_llm = ChatOpenAI(
    model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"),
    temperature=0,
    timeout=60,
    max_retries=2,
)
ANALYST_PROMPT = ChatPromptTemplate.from_messages(
    [
        ("system", "You are a careful data analyst. Only use the provided rows to answer."),
        (
            "human",
            """Question: {question}
SQL: {sql}
Rows (JSON): {rows_json}

Tasks:
1) If rows are empty, say that plainly and suggest a tighter query.
2) Provide up to 5 concise insights (counts, trends, top/bottom, ranges).
3) If categories with metrics appear, include a compact ranking.
4) Never fabricate values; if unsure, state the limitation.
Return a short, plain answer.""",
        ),
    ]
)
def interpret_rows(question: str, sql: str, rows: Any) -> str:
    rows_json = json.dumps(rows, ensure_ascii=False)[:12000]  # trim huge outputs
    return (ANALYST_PROMPT | analyst_llm | StrOutputParser()).invoke(
        {"question": question, "sql": sql, "rows_json": rows_json}
    )

analyst = Agent(
    role="Insights Analyst",
    goal="Explain results succinctly with counts, trends, and rankings. Never fabricate.",
    backstory="Business analyst who writes crisp, actionable insights from tabular data.",
    tools=[],  # reasoning-only; we call a deterministic prompt above
    allow_delegation=False,
)

# -----------------------------------------------------------------------------
# Mini-crew runners (robust in production)
# -----------------------------------------------------------------------------
def _run_planner(question: str) -> str:
    task = Task(
        description=(
            "Generate ONE minimal, correct SQL Server SELECT that answers the user's question. "
            "Use the nl2sql_tool. Return ONLY the SQL."
        ),
        expected_output="A single SQL string.",
        agent=planner,
    )
    crew = Crew(agents=[planner], tasks=[task], process=Process.sequential)
    out = crew.kickoff(inputs={"question": question})
    sql = (out.raw or "").strip()
    if not sql:
        # Deterministic fallback: call chain directly
        sql = generate_and_validate_sql(question)
    return sql

def _run_guard(sql: str, user_id: int, limit: Optional[int] = None) -> str:
    task = Task(
        description=(
            "Harden the provided SQL: enforce read-only, reject SELECT *, scope all private tables "
            f"to user_id={user_id}, and cap rows to a reasonable limit. Return ONLY the final safe SQL."
        ),
        expected_output="A single safe SQL string.",
        agent=guardian,
    )
    crew = Crew(agents=[guardian], tasks=[task], process=Process.sequential)
    out = crew.kickoff(inputs={"sql": sql, "user_id": user_id, "limit": limit})
    safe_sql = (out.raw or "").strip() or sql
    # Server-side verification regardless of agent output
    return safe_sql_transform(safe_sql, user_id=user_id, requested_limit=limit)

def _run_exec(sql: str) -> Any:
    task = Task(
        description="Execute the SQL and return rows as a JSON-like list.",
        expected_output="Rows as list[dict] (or string repr if engine unavailable).",
        agent=executor,
    )
    crew = Crew(agents=[executor], tasks=[task], process=Process.sequential)
    out = crew.kickoff(inputs={"sql": sql})
    rows = out.raw
    # If the tool returned a string (db.run fallback), try to json-load, else keep string
    if isinstance(rows, str):
        try:
            rows = json.loads(rows)
        except Exception:
            pass
    return rows

def _run_analyst(question: str, sql: str, rows: Any) -> str:
    # Deterministic LLM summarizer (outside of Crew for predictability)
    return interpret_rows(question, sql, rows)

# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------
def run_crewai_pipeline(question: str, user_id: int, limit: Optional[int] = None) -> Dict[str, Any]:
    """
    End-to-end execution with robust safety and structured results.
    """
    try:
        sql = _run_planner(question)
        logger.info("Planner SQL: %s", sql)

        safe_sql = _run_guard(sql, user_id=user_id, limit=limit)
        logger.info("Safe SQL: %s", safe_sql)

        rows = _run_exec(safe_sql)
        # Normalize rows to list[dict] where possible
        if isinstance(rows, str) and rows.startswith("[") and rows.endswith("]"):
            try:
                rows = json.loads(rows)
            except Exception:
                pass

        answer = _run_analyst(question, safe_sql, rows)
        return {"sql": safe_sql, "rows": rows, "answer": answer}

    except ValidationError as ve:
        logger.exception("Validation error")
        raise
    except Exception as e:
        logger.exception("Pipeline error")
        raise

# -----------------------------------------------------------------------------
# Demo
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    uid = int(os.getenv("DEMO_USER_ID", "138"))
    q = "Average calories per meal category with top 5 examples."
    result = run_crewai_pipeline(q, uid)
    print("\nSQL:\n", result["sql"])
    preview = result["rows"]
    if isinstance(preview, list) and preview and isinstance(preview[0], dict):
        print("\nRows (first 5):\n", json.dumps(preview[:5], indent=2, ensure_ascii=False))
    else:
        print("\nRows (raw preview):\n", str(preview)[:500])
    print("\nAnswer:\n", result["answer"])
