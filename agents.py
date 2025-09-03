"""
ZINZI Agentic Framework — Local Review Loops per Agent (Planner → Executor → Reviewer) to ensure accuracy

Prereqs:
  pip install -U crewai crewai-tools langchain langchain-openai langchain-community sqlalchemy pyodbc pydantic python-dotenv
Environment:
  OPENAI_API_KEY=... ; OPENAI_MODEL=gpt-4o-mini ; BACKGROUND_FILE=agents_tools_guide.md
"""

from __future__ import annotations
import os, re, json, logging, urllib.parse
from typing import Dict, Any, Optional, List
from pydantic import BaseModel, Field
from crewai import Agent, Task, Crew, Process
from crewai.tools import BaseTool
from langchain_openai import ChatOpenAI
from langchain.chains import create_sql_query_chain
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from langchain_community.utilities import SQLDatabase
from sqlalchemy import text
from sqlalchemy.engine import Engine, Result

# -------------------- Logging --------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
log = logging.getLogger("zinzi.local_loops")

# -------------------- DB + LangChain --------------------
def mssql_uri(driver="ODBC Driver 17 for SQL Server", server=r"localhost\SQLExpress", database="ZANZA", trusted=True):
    odbc = f"Driver={{{driver}}};Server={server};Database={database};Trusted_Connection={'Yes' if trusted else 'No'};TrustServerCertificate=Yes;"
    return "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(odbc)

DB_URI = mssql_uri()
db = SQLDatabase.from_uri(DB_URI, sample_rows_in_table_info=2)
ENGINE: Optional[Engine] = getattr(db, "engine", None) or getattr(db, "_engine", None)

DEFAULT_CAP = int(os.getenv("SQL_DEFAULT_CAP", "500"))
MAX_CAP = int(os.getenv("SQL_MAX_CAP", "5000"))
BACKGROUND_FILE = os.getenv("BACKGROUND_FILE", "agents_tools_guide.md")
PRIVATE_TABLES = {"user_preferences", "user_metrics"}

FORBIDDEN_SQL = re.compile(r"\b(UPDATE|INSERT|DELETE|MERGE|EXEC|EXECUTE|DROP|ALTER|TRUNCATE|CREATE|GRANT|REVOKE)\b", re.I)
READONLY_HEAD = re.compile(r"^\s*(?:--.*?$|/\*.*?\*/\s*)*(?:WITH\b.*?\bSELECT\b|SELECT\b)", re.I | re.S | re.M)
STAR_PAT = re.compile(r"\bSELECT\s+\*", re.I)
ALIAS_PAT = re.compile(r"\b(?:FROM|JOIN)\s+([a-zA-Z0-9_]+)(?:\s+AS)?\s+([a-zA-Z0-9_]+)", re.I)

llm = ChatOpenAI(model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"), temperature=0, timeout=60, max_retries=2)
sql_gen_chain = create_sql_query_chain(llm, db)
_validator_prompt = ChatPromptTemplate.from_messages([
    ("system", f"You are a meticulous SQL Server reviewer. Avoid SELECT *; use explicit columns. "
               f"If large, add ORDER BY and TOP {DEFAULT_CAP} or OFFSET/FETCH. Return ONLY SQL."),
    ("human", "{query}")
])
validation_chain = _validator_prompt | llm | StrOutputParser()

def generate_and_validate_sql(question: str) -> str:
    raw_sql = sql_gen_chain.invoke({"question": question})
    return validation_chain.invoke({"query": raw_sql})

# -------------------- Tools --------------------
class NL2SQLInput(BaseModel):
    question: str
class NL2SQLTool(BaseTool):
    name, description, args_schema = "nl2sql_tool", "Generate SQL Server SELECT for a question.", NL2SQLInput
    def _run(self, question: str) -> str: return generate_and_validate_sql(question)

class GuardSQLInput(BaseModel):
    sql: str; user_id: int; limit: Optional[int] = None
class GuardSQLTool(BaseTool):
    name, description, args_schema = "guard_sql_tool", "Read-only, explicit cols, user_id scope, row caps.", GuardSQLInput
    def _run(self, sql: str, user_id: int, limit: Optional[int] = None) -> str:
        if not READONLY_HEAD.search(sql) or FORBIDDEN_SQL.search(sql): raise ValueError("Non-read-only SQL.")
        if STAR_PAT.search(sql): raise ValueError("SELECT * not allowed.")
        tables = [t.lower() for t in db.get_usable_table_names()]
        used = sorted({t for t in tables if re.search(rf"\b{re.escape(t)}\b", sql.lower())})
        priv = [t for t in used if t in PRIVATE_TABLES]
        if priv and not re.search(r"\buser_?id\s*=", sql, re.I):
            # alias-aware
            alias_map = {}
            for tbl, alias in ALIAS_PAT.findall(sql):
                alias_map.setdefault(tbl.lower(), []).append(alias.lower())
            preds=[]
            for t in priv:
                aliases = alias_map.get(t, [])
                preds += [f"{a}.user_id = {user_id}" for a in aliases] or [f"{t}.user_id = {user_id}"]
            clause = "(" + " AND ".join(preds) + ")"
            if re.search(r"\bWHERE\b", sql, re.I):
                sql = re.sub(r"\bWHERE\b", f"WHERE {clause} AND", sql, 1, flags=re.I)
            else:
                anchor = re.search(r"\b(GROUP BY|ORDER BY|HAVING|OPTION|FOR JSON|FOR XML)\b", sql, re.I)
                sql = sql[:anchor.start()] + f" WHERE {clause} " + sql[anchor.start():] if anchor else sql.rstrip().rstrip(";") + f" WHERE {clause};"
        cap = min(int(limit or DEFAULT_CAP), MAX_CAP)
        if not re.search(r"\bSELECT\s+TOP\s+\d+\b", sql, re.I) and not re.search(r"\bOFFSET\s+\d+\s+ROWS\b", sql, re.I):
            if not re.match(r"^\s*(?:--.*?$|/\*.*?\*/\s*)*WITH\b", sql, re.I | re.S | re.M):
                sql = re.sub(r"^\s*SELECT\s+DISTINCT\s+", f"SELECT DISTINCT TOP {cap} ", sql, 1, flags=re.I)
                sql = re.sub(r"^\s*SELECT\s+", f"SELECT TOP {cap} ", sql, 1, flags=re.I)
        return sql

class ExecSQLInput(BaseModel):
    sql: str
class ExecSQLTool(BaseTool):
    name, description, args_schema = "exec_sql_tool", "Execute SQL and return rows as list[dict].", ExecSQLInput
    def _run(self, sql: str) -> Any:
        if ENGINE is None: return db.run(sql)
        with ENGINE.begin() as conn:
            result: Result = conn.execute(text(sql))
            return [dict(row._mapping) for row in result]

class ReadFileInput(BaseModel):
    path: str; max_chars: int = 3000
class ReadFileTool(BaseTool):
    name, description, args_schema = "read_file_tool", "Read a local text/markdown file (truncated).", ReadFileInput
    def _run(self, path: str, max_chars: int = 3000) -> str:
        try:
            with open(path, "r", encoding="utf-8") as f: data = f.read()
            return data[:max_chars]
        except Exception as e:
            return f"[FILE_READ_ERROR] {e}"

# -------------------- Local 3-Subagent Loop (Planner → Executor → Reviewer) --------------------
MAX_ITERS = int(os.getenv("REVIEW_MAX_ITERS", "3"))

def run_local_loop(agent_name: str,
                   planner: Agent, executor: Agent, reviewer: Agent,
                   plan_desc: str, exec_desc: str, review_desc: str,
                   inputs: Dict[str, Any]) -> str:
    """
    Reviewer must output JSON: {"status":"PASS|LOOP","artifact":"...", "feedback":"..."}.
    Loops until PASS or max iters; returns artifact (maybe reviewer-corrected).
    """
    critique = ""
    artifact_out = ""
    for _ in range(MAX_ITERS):
        t_plan = Task(description=f"{plan_desc}\n\nContext:\nquestion={{question}}\ncritique={{critique}}",
                      expected_output="Short plan (<=8 lines).", agent=planner)
        t_exec = Task(description=f"{exec_desc}\n\nUse the plan above.\nReturn ONLY the artifact (string/JSON).",
                      expected_output="Artifact only.", agent=executor, context=[t_plan])
        t_rev  = Task(description=f"{review_desc}\n\nReturn control JSON only.",
                      expected_output='{"status":"PASS|LOOP","artifact":"...","feedback":"..."}',
                      agent=reviewer, context=[t_plan, t_exec])
        crew = Crew(agents=[planner, executor, reviewer], tasks=[t_plan, t_exec, t_rev], process=Process.sequential)
        out = crew.kickoff(inputs={**inputs, "critique": critique})
        raw = (out.raw or "").strip()
        # Extract last JSON block from reviewer output
        try:
            start, end = raw.rfind("{"), raw.rfind("}")
            ctrl = json.loads(raw[start:end+1]) if start != -1 else {}
        except Exception:
            ctrl = {"status":"LOOP","artifact":artifact_out,"feedback":"Malformed review JSON"}
        status = (ctrl.get("status") or "").upper()
        artifact_out = ctrl.get("artifact", artifact_out)
        critique = ctrl.get("feedback","")
        if status == "PASS": return artifact_out
    return artifact_out  # best effort after max iters

# -------------------- Subagent Triples per Agent --------------------
def make_intent_triple():
    return (
      Agent(role="Intent Planner", goal="Plan how to classify the user query.", tools=[], allow_delegation=False),
      Agent(role="Intent Executor", goal="Output JSON: {intent, targets[], confidence, reasons}.", tools=[], allow_delegation=False),
      Agent(role="Intent Reviewer", goal="Validate JSON & alignment; PASS or LOOP with fixes.", tools=[], allow_delegation=False),
    )

def make_background_triple():
    return (
      Agent(role="BG Planner", goal="Plan what to extract from background file.", tools=[], allow_delegation=False),
      Agent(role="BG Executor", goal="Read file and extract <=1200 char relevant snippet.", tools=[ReadFileTool()], allow_delegation=False),
      Agent(role="BG Reviewer", goal="Check relevance and length; PASS or LOOP.", tools=[], allow_delegation=False),
    )

def make_domain_triple(name: str):
    return (
      Agent(role=f"{name} Planner", goal=f"Plan minimal SQL for {name}.", tools=[], allow_delegation=False),
      Agent(role=f"{name} Executor", goal=f"Generate SQL via NL2SQLTool for {name}.", tools=[NL2SQLTool()], allow_delegation=False),
      Agent(role=f"{name} Reviewer", goal="Validate SQL vs spec; fix cols; PASS or LOOP.", tools=[], allow_delegation=False),
    )

# -------------------- Public steps using local loops --------------------
def classify_intent(question: str) -> Dict[str, Any]:
    P,E,R = make_intent_triple()
    plan = "Decide which domain(s) the query targets (meals/weight/wearables/mixed)."
    execd= ("Produce compact JSON only with keys: intent (meals|weight|wearables|mixed), "
            "targets (array), confidence (0-1), reasons (string). No extra text.")
    review=("Ensure JSON schema is correct, intent matches question, and targets set is coherent. "
            "If fixes needed, return corrected JSON in 'artifact'.")
    art = run_local_loop("intent", P,E,R, plan, execd, review, {"question": question})
    try: return json.loads(art)
    except Exception: return {"intent":"meals","targets":["meals"],"confidence":0.5,"reasons":"fallback"}

def load_background_snippet(question: str) -> str:
    P,E,R = make_background_triple()
    plan = "Pick minimal guidance from background file to help agents/tools choose correctly."
    execd= f"Use read_file_tool with path='{BACKGROUND_FILE}'. Extract <=1200 chars most relevant to the question. Return ONLY snippet text."
    review="Check snippet is under 1200 chars and relevant; trim or refine if needed and return snippet in 'artifact'."
    return run_local_loop("background", P,E,R, plan, execd, review, {"question": question, "path": BACKGROUND_FILE, "max_chars": 3000})[:1200]

def gen_domain_sql(domain: str, question: str, spec_yaml: str, background: str) -> str:
    P,E,R = make_domain_triple(domain.capitalize())
    plan = f"From spec + background, choose exact tables/columns and constraints for {domain}."
    execd= "Use nl2sql_tool to emit ONE SQL Server SELECT. No SELECT *. No prose."
    review=("Verify SQL matches spec & domain; fix invalid columns/joins; ensure explicit cols; "
            "return corrected SQL in 'artifact'. PASS when valid.")
    return run_local_loop(domain, P,E,R, plan, execd, review, {"question": question, "spec": spec_yaml, "background": background})

# -------------------- Guard + Execute + Analyst + Final Review (unchanged shape) --------------------
class GuardSQLInput(BaseModel):
    sql: str; user_id: int; limit: Optional[int] = None

privacy_guard = Agent(role="Privacy Guard", goal="Harden SQL (read-only, explicit cols, user_id scope, caps).", tools=[GuardSQLTool()], allow_delegation=False)
sql_executor_agent = Agent(role="SQL Executor", goal="Run safe SQL and return rows.", tools=[ExecSQLTool()], allow_delegation=False)
final_reviewer = Agent(role="Final Review Crew", goal="Validate final JSON for schema/privacy/intent.", tools=[], allow_delegation=False)

def harden_sql(sql: str, user_id: int, limit: Optional[int]) -> str:
    t = Task(description=f"Harden SQL for user_id={user_id}; return ONLY safe SQL.", expected_output="SQL", agent=privacy_guard)
    c = Crew(agents=[privacy_guard], tasks=[t], process=Process.sequential)
    out = (c.kickoff(inputs={"sql": sql, "user_id": user_id, "limit": limit}).raw or "").strip()
    # server-side verify anyway
    return GuardSQLTool()._run(out or sql, user_id=user_id, limit=limit)

def exec_sql(sql: str) -> Any:
    t = Task(description="Execute SQL and return rows as list[dict] (or raw repr).", expected_output="Rows payload.", agent=sql_executor_agent)
    c = Crew(agents=[sql_executor_agent], tasks=[t], process=Process.sequential)
    rows = c.kickoff(inputs={"sql": sql}).raw
    if isinstance(rows, str):
        try: rows = json.loads(rows)
        except Exception: pass
    return rows

ANALYST_JSON_PROMPT = ChatPromptTemplate.from_messages([
    ("system", "Return STRICT JSON only: {answer, highlights[], tables[], queries[], meta{}}. No extra text."),
    ("human", "Question: {question}\nSQLs: {sqls}\nRows: {rows_json}\nMeta: {meta}\nReturn ONLY JSON.")
])
analyst_llm = ChatOpenAI(model=os.getenv("OPENAI_MODEL", "gpt-4o-mini"), temperature=0)
def analyze_structured(question: str, sql_map: Dict[str,str], rows_map: Dict[str,Any], user_id: int) -> str:
    msg = ANALYST_JSON_PROMPT.format(
        question=question,
        sqls=json.dumps(sql_map, ensure_ascii=False),
        rows_json=json.dumps(rows_map, ensure_ascii=False)[:16000],
        meta=json.dumps({"user_id":user_id,"limits":{"top":DEFAULT_CAP}}, ensure_ascii=False)
    ).to_messages()
    return (analyst_llm | StrOutputParser()).invoke(msg).strip()

def final_json_review(payload: str, intent: Dict[str,Any]) -> str:
    t = Task(description=f"Validate JSON structure/privacy and match to intent={intent}. Return corrected JSON only if needed; else original JSON.", expected_output="JSON", agent=final_reviewer)
    c = Crew(agents=[final_reviewer], tasks=[t], process=Process.sequential)
    raw = (c.kickoff(inputs={"json_payload": payload}).raw or "").strip()
    try:
        start, end = raw.find("{"), raw.rfind("}")
        return raw[start:end+1] if (start!=-1 and end!=-1) else payload
    except Exception:
        return payload

# -------------------- Orchestrator API --------------------
def run_zinzi_pipeline(question: str, user_id: int, limit: Optional[int] = None) -> Dict[str, Any]:
    # Intent loop
    intent = classify_intent(question)
    targets = intent.get("targets") or [intent.get("intent","meals")]
    # Background loop
    bg_snippet = load_background_snippet(question)
    # (Optional) Spec is lightweight and can be added similarly; we keep it implicit here for brevity.

    # Domain loops (parallelizable by caller if desired)
    sql_map: Dict[str,str] = {}
    for d in targets:
        sql_map[d] = gen_domain_sql(d, question, spec_yaml="(implicit)", background=bg_snippet)

    # Guard + Execute per domain
    safe_sql_map, rows_map = {}, {}
    for d, sql in sql_map.items():
        if not sql: continue
        safe_sql_map[d] = harden_sql(sql, user_id, limit)
        rows_map[d] = exec_sql(safe_sql_map[d])

    # Analyst + Final review
    structured = analyze_structured(question, safe_sql_map, rows_map, user_id)
    final_json = final_json_review(structured, intent)

    return {
        "intent": intent,
        "background": bg_snippet,
        "sql": safe_sql_map,
        "rows": rows_map,
        "answer": final_json
    }

# -------------------- CLI demo --------------------
if __name__ == "__main__":
    uid = int(os.getenv("DEMO_USER_ID", "138"))
    q = os.getenv("DEMO_QUESTION", "Show my fiber-rich meals and last 14 days of weight and steps.")
    out = run_zinzi_pipeline(q, uid)
    print("\nINTENT:\n", json.dumps(out["intent"], indent=2))
    print("\nSQL:\n", json.dumps(out["sql"], indent=2))
    print("\nROWS PREVIEW:\n", {k: (v[:2] if isinstance(v, list) else str(v)[:240]) for k,v in out["rows"].items()})
    print("\nSTRUCTURED ANSWER:\n", out["answer"])
