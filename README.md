# Phreak - Elixir implementation of the Phreak (lazy Rete) algorithm
---

## Overview

**Layout:**
```
 phreak/
   mix.exs                     – project config
   lib/
     phreak.ex                 – public API facade
     application.ex            – OTP app stub
     phreak/session.ex         – runtime session & API
     phreak/compiler.ex        – runtime rule compiler from JSON
     phreak/engine.ex          – agenda scheduler + linker implementation
     phreak/node.ex            – behaviour for alpha/beta/terminal nodes
     phreak/nodes/*.ex         – concrete node modules (alpha, beta, join, acc)
     phreak/util/bitset.ex     – tiny bit‑mask helper for segment linking
```

## Quick Start

```elixir
# Create an empty session
session = Phreak.new()

# Define a simple rule with variable joins (implicit AND)
diabetes_rule = %{
  "name" => "flag_diabetes",
  "conditions" => [
    %{
      "type" => "patient",
      "constraints" => [
        %{"field" => "id", "op" => "bind", "var" => "patient_id"},
        %{"field" => "age", "op" => ">", "value" => 50}
      ]
    },
    %{
      "type" => "lab",
      "constraints" => [
        %{"field" => "patient_id", "op" => "bind", "var" => "patient_id"},
        %{"field" => "name", "op" => "eq", "value" => "a1c"},
        %{"field" => "value", "op" => ">", "value" => 6.5}
      ]
    }
  ],
  "actions" => [
    %{"type" => "assert", "fact" => ["risk", %{"var" => "patient_id"}, "diabetes"]}
  ]
}

# The engine automatically creates beta joins for shared variables!
{:ok, session} = Phreak.add_rule(session, diabetes_rule)

# Assert facts - they will be joined on patient_id
session
|> Phreak.assert({:patient, id: 1, age: 62})
|> Phreak.assert({:patient, id: 2, age: 45})
|> Phreak.assert({:lab, patient_id: 1, name: "a1c", value: 7.1})
|> Phreak.assert({:lab, patient_id: 2, name: "a1c", value: 7.1}) # Won't fire - patient too young
|> Phreak.fire_all()


session = Phreak.assert(session, {:patient, id: 1, age: 62})
session = Phreak.assert(session, {:patient, id: 2, age: 45})
session = Phreak.assert(session, {:lab, patient_id: 1, name: "a1c", value: 7.1})
session = Phreak.assert(session, {:lab, patient_id: 2, name: "a1c", value: 7.1}) # Won't fire - patient too young
session = Phreak.fire_all(session)
```

## How Beta Joins Work

When multiple fact patterns in an AND condition share variables, the engine automatically:
1. Creates alpha nodes for each fact pattern
2. Creates beta join nodes that test variable equality
3. Only propagates when facts have matching variable values

For example, in the diabetes rule above:
- The patient fact binds its `id` field to `patient_id` variable
- The lab fact also binds its `patient_id` field to the same variable
- A beta join ensures only matching patient/lab pairs fire the rule

## Compound Conditions with Joins

```elixir
# Complex rule with nested logic and multiple joins
complex_rule = %{
  "name" => "diabetes_risk_assessment",
  "conditions" => %{
    "and" => [
      # Patient must be over 40
      %{
        "type" => "patient",
        "constraints" => [
          %{"field" => "id", "op" => "bind", "var" => "pid"},
          %{"field" => "age", "op" => ">", "value" => 40}
        ]
      },
      # AND either high A1C OR (high glucose AND not on metformin)
      %{
        "or" => [
          # High A1C for same patient
          %{
            "type" => "lab",
            "constraints" => [
              %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
              %{"field" => "name", "op" => "eq", "value" => "a1c"},
              %{"field" => "value", "op" => ">", "value" => 6.5}
            ]
          },
          # OR high glucose without medication (both must be for same patient)
          %{
            "and" => [
              %{
                "type" => "lab",
                "constraints" => [
                  %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
                  %{"field" => "name", "op" => "eq", "value" => "glucose"},
                  %{"field" => "value", "op" => ">", "value" => 126}
                ]
              },
              %{
                "not" => %{
                  "type" => "medication",
                  "constraints" => [
                    %{"field" => "patient_id", "op" => "bind", "var" => "pid"},
                    %{"field" => "name", "op" => "eq", "value" => "metformin"}
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
  },
  "actions" => [
    %{"type" => "assert", "fact" => ["alert", {"var" => "pid"}, "diabetes_risk", "high"]}
  ]
}
```

## JSON Rule Format

### Simple Format (Implicit AND)
When `conditions` is an array, all conditions must match (AND):
```json
{
  "name": "rule_name",
  "conditions": [
    { "type": "fact_type", "constraints": [...] },
    { "type": "another_type", "constraints": [...] }
  ],
  "actions": [...]
}
```

### Compound Format
Use `and`, `or`, `not` for complex logic:
```json
{
  "name": "rule_name",
  "conditions": {
    "and": [
      { "type": "fact1", "constraints": [...] },
      {
        "or": [
          { "type": "fact2", "constraints": [...] },
          { "not": { "type": "fact3", "constraints": [...] } }
        ]
      }
    ]
  },
  "actions": [...]
}
```

### Constraints
- `field`: Field name to test
- `op`: Operation
  - `"bind"`: Bind field value to variable (for joins)
  - `"eq"`: Equal to value or variable
  - `">"`, `"<"`, `">="`, `"<="`: Numeric comparisons
  - `"!="`: Not equal
- `value`: Literal value for comparison
- `var`: Variable name for binding or cross-fact joins

### Actions
- `type`: Action type ("assert", "retract", "modify", "call")
- Additional fields based on action type

## Architecture

The Phreak implementation uses a modified Rete network:
1. **Alpha nodes**: Test individual facts against patterns
2. **Beta nodes**: Join facts with matching variable values
3. **Logical gates**: Implement AND/OR/NOT operations
4. **Terminal nodes**: Execute actions when rules fire

Facts flow through alpha nodes first, then through beta joins (if variables are shared),
and finally through logical gates to terminal nodes that execute actions.

## Roadmap
* [x] Alpha network compilation (pattern + guard) - IMPLEMENTED
* [x] Runtime rule definition from JSON - IMPLEMENTED
* [x] Compound conditions (AND/OR/NOT) - IMPLEMENTED
* [x] Beta joins for cross-fact variable matching - IMPLEMENTED
* [ ] Terminal nodes and action execution
* [ ] Segment linker w/ BitSet masks
* [ ] Truth‑maintenance / retract support
* [ ] Complex actions (modify, function calls)
* [ ] Rule priorities and conflict resolution
* [ ] Accumulators & temporal operators
* [ ] Rule validation and debugging tools
* [ ] REST API for rule management
