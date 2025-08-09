def lowercase_keys(data):
    """
    Recursively convert all dictionary keys in the data to lowercase.
    Handles nested dictionaries and lists.
    """
    if isinstance(data, dict):
        return {k.lower(): lowercase_keys(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [lowercase_keys(item) for item in data]
    else:
        return data