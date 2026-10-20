# Lists every description and naming problem in a compiled ARM template (the input), one per line.
# The README is generated from the descriptions, so a missing one is a CI error, not a style nit.
# The naming prefixes are checked here too: the compiled template names every symbol.

def missing: (.metadata.description // "") == "";
def imported: (.key | startswith("_")) or (.value.metadata["__bicep_imported_from!"] != null);

[ (if (.metadata.name // "") == "" then "metadata name is missing" else empty end),
  (if missing then "metadata description is missing" else empty end),

  # Every parameter, output, type and property has a description
  (.parameters // {} | to_entries[] | select(.value | missing) | "parameter \(.key) has no @description"),
  (.outputs // {} | to_entries[] | select(.value | missing) | "output \(.key) has no @description"),
  (.definitions // {} | to_entries[] | select(imported | not)
    | (select(.value | missing) | "type \(.key) has no @description"),
      (.key as $type | .value.properties // {} | to_entries[] | select(.value | missing)
        | "property \($type).\(.key) has no @description")),

  # Descriptions say what a value is for; the generator adds defaults, examples and what is required
  (.. | objects | .metadata? | objects | .description? | strings
    | (select(test("img\\.shields\\.io")) | "a description contains a badge; the README says what is required"),
      (select(test("(?i)\\b(example|default)s?:")) | "a description lists an example or a default: use @metadata({ example: … }); defaults come from the template")),

  # Prefixes: parameters p, variables v, resources r, modules m, outputs o; types end in Type
  (.parameters // {} | keys[] | select(test("^p[A-Z]") | not) | "parameter \(.) needs the prefix p"),
  (.outputs // {} | keys[] | select(test("^o[A-Z]") | not) | "output \(.) needs the prefix o"),
  (.variables // {} | keys[] | select(startswith("$") or startswith("_") | not) | select(test("^v[A-Z]") | not)
    | "variable \(.) needs the prefix v"),
  (.resources | objects | to_entries[]
    | if .value.type == "Microsoft.Resources/deployments"
      then select(.key | test("^m[A-Z]") | not) | "module \(.key) needs the prefix m"
      else select(.key | test("^r[A-Z]") | not) | "resource \(.key) needs the prefix r" end),
  (.definitions // {} | to_entries[] | select(imported | not) | select(.key | test("Type$") | not)
    | "type \(.key) needs the suffix Type")
] | unique[]
