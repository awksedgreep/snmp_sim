# Refactoring Rules

## Core Principles

1. **Be Judicious and Disciplined**
   - Follow the exact process without creative deviations
   - Stick to the plan, don't try to fix unrelated issues
   - Resist the urge to improve or optimize during refactoring

2. **Minimal Changes Only**
   - Only move existing functions, don't modify their behavior
   - Don't add new functionality during refactoring
   - Don't change function signatures, inputs, or outputs
   - Keep the exact same logic and implementation

3. **Incremental Process**
   - Move one function at a time
   - Comment out original function instead of deleting immediately
   - Test after each step to ensure nothing breaks
   - Maintain full test suite pass status after each step

4. **No Scope Creep**
   - Don't fix bugs found during refactoring
   - Don't optimize performance during refactoring
   - Don't improve code style during refactoring
   - Don't add error handling during refactoring

## Step-by-Step Process (SAFER APPROACH)

1. **Copy Function to OidHandler**
   - Copy function exactly as-is to `OidHandler`
   - Make it public if it needs to be called from `device.ex`
   - **DO NOT CHANGE ANY CODE INSIDE FUNCTIONS** - Only move entire functions

2. **Comment Out Original Function**
   - Comment out the original function in `device.ex` (don't delete yet)
   - This preserves the original for easy rollback

3. **Ensure References/Aliases Exist**
   - Make sure `alias SnmpSim.Device.OidHandler` exists in `device.ex`
   - Update all calls to use `OidHandler.function_name`

4. **Test** - OPTIONAL, recommended for final step
   - Run tests to ensure nothing is broken
   - If tests fail, investigate delegation issues only
   - Don't fix unrelated test failures

5. **Repeat for Next Function**
   - Only proceed if tests pass
   - Move to next function using same process

6. **Clean Up at End**
   - After ALL functions are moved and tested, remove commented functions
   - This final cleanup step removes all the commented-out code

## What NOT to Do

- ❌ Don't try to fix unrelated issues
- ❌ Don't optimize or improve code during refactoring
- ❌ Don't change function behavior
- ❌ Don't add new features
- ❌ Don't fix bugs unless they're directly caused by the refactoring
- ❌ Don't use destructive git commands
- ❌ Don't make multiple changes at once
- ❌ **NEVER** change code inside functions during the move

## What TO Do

- ✅ Move functions exactly as they are
- ✅ Update delegation calls precisely
- ✅ Test after each small change
- ✅ Keep changes focused and minimal
- ✅ Follow the process step by step
- ✅ Be patient and methodical

## CRITICAL RULES

- **NEVER** delete original functions until ALL moves are complete
- **NEVER** modify function logic during the move
- **NEVER** try to fix multiple issues at once
- **ALWAYS** test after each individual function move
- **ALWAYS** use exact same function signatures and behavior
- **DO NOT CHANGE ANY CODE INSIDE FUNCTIONS** - Only move entire functions
