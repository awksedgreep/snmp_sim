  🎯 ESSENTIAL TESTING RULES

  1. ALL TESTS MUST USE SNMPSimulator - Never hardcode "127.0.0.1" or real hosts
  2. ALL TIMEOUTS MUST BE SHORT - Use 200ms max, all tests are local
  3. FOLLOW EXISTING PATTERNS - If bulk_operations_test.exs already uses simulator correctly, don't touch it
  4. TEST FIRST - Check current status before making changes
  5. SIMULATOR SETUP - Always use SNMPSimulator.create_test_device() and device.community
  6. NEVER WRITE MEANINGLESS TESTS - FORBIDDEN patterns that don't actually test anything:
     - assert match?({:ok, _} | {:error, _}, result)
     - assert match?({:ok, _}, result) or match?({:error, _}, result)
     - Any assertion that passes whether a function succeeds OR fails
     
     Instead, write tests that verify specific expected behavior:
     - If operation should succeed: assert {:ok, _} = result
     - If operation should fail: assert {:error, _} = result
     - If testing error handling: assert {:error, :specific_reason} = result
     - If result format varies: use case statements with specific assertions for each outcome
     
     Every test assertion must verify something meaningful. If your test would pass regardless 
     of whether the function works correctly, the test is useless and must be rewritten.
7.  YOU MUST SEARCH FOR ROOT CAUSES - If a test fails, don't just fix the symptom. Find the root cause and fix it.