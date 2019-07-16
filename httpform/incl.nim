type
    FormError = object of Exception

proc newFile(path: string, size: int, ctype: string, filename: string): JsonNode = 
    result = newJObject()
    result["path"] = newJString(path)
    result["size"] = newJInt(size)
    result["type"] = newJString(ctype)
    result["name"] = newJString(filename)

proc delQuote(s: string): string =
    # "a" => a
    var length = s.len()
    if s == "\"\"": 
        return ""
    if length < 3: 
        return s
    if s[0] == '\"' and s[length-1] == '\"': 
        return s[1..length-2]
    return s