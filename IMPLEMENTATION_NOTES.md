# Phreak Engine - fire_all Implementation Notes

## Overview

The `fire_all` function is the core execution mechanism in the Phreak rule engine. It processes all activations in the agenda queue, executing the associated actions for each matched rule.

## Key Implementation Details

### 1. Function Signature
```elixir
@spec fire_all(Session.t(), keyword()) :: {:ok, Session.t(), non_neg_integer()}
```
- Returns a tuple with `:ok`, the updated session, and the count of fired rules
- Accepts options including `max_fires` to limit execution

### 2. Agenda Processing
- The agenda is a FIFO queue (`:queue`) containing rule activations
- Each activation contains:
  - `rule`: The rule name
  - `facts`: The matched facts
  - `bindings`: Variable bindings from the rule matching
  - `actions`: List of actions to execute

### 3. Fire Loop
- Implements a recursive loop that:
  1. Dequeues activations from the agenda
  2. Executes each activation
  3. Counts fired rules
  4. Respects the `max_fires` limit (defaults to `:infinity`)

### 4. Fact Storage
- Facts are stored in working memory (`session.wm`)
- Original facts are stored under a `:facts` key for retraction support
- Alpha nodes store facts in their own memory locations (by alpha node ID)

### 5. Fact Format Normalization
- Supports both map-style facts (`%{type: :patient, ...}`) and tuple-style facts (`{:patient, [...]}`)
- Internally normalizes to tuple format for consistency

## Test Coverage

The implementation is thoroughly tested with:
- Basic firing scenarios
- Variable binding and joins
- OR/AND/NOT conditions
- Max fires limiting
- Empty agenda handling
- Edge cases (0 max_fires)

## Future Enhancements

1. **Action Execution**: Currently, actions are just logged. A real implementation would need:
   - Action handler registry
   - Side effect management
   - Action result handling

2. **Salience/Priority**: The current implementation uses FIFO ordering. Future versions could add:
   - Rule priority/salience
   - Conflict resolution strategies
   - Agenda sorting

3. **Truth Maintenance**: Full retraction support would require:
   - Tracking fact dependencies
   - Propagating retractions through the network
   - Removing dependent activations from the agenda
