-- NetProtocolTest.client.lua
-- DoD 테스트: 100회 반복 호출 안정성 + unknown command 테스트

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local NetClient = require(Client.NetClient)

local function runTests()
	print("========================================")
	print("[TEST] NetProtocol v1 DoD 테스트 시작")
	print("========================================")
	
	-- NetClient 초기화 대기
	task.wait(2)
	local initSuccess = NetClient.Init()
	if not initSuccess then
		warn("[TEST] NetClient 초기화 실패")
		return
	end
	
	local passed = 0
	local failed = 0
	
	-- 테스트 1: Ping 100회 반복
	print("\n[TEST 1] Ping 100회 반복 호출...")
	local pingSuccess = 0
	local pingFail = 0
	local startTime = os.clock()
	
	for i = 1, 100 do
		local ok, result = NetClient.Ping()
		if ok and result and result.ok == true then
			pingSuccess += 1
		else
			pingFail += 1
			warn("[TEST 1] Ping 실패 #" .. i, ok, result)
		end
	end
	
	local pingTime = os.clock() - startTime
	print(string.format("[TEST 1] Ping 결과: %d/100 성공 (%.2f초)", pingSuccess, pingTime))
	
	if pingSuccess == 100 then
		passed += 1
		print("[TEST 1] PASSED ✓")
	else
		failed += 1
		print("[TEST 1] FAILED ✗")
	end
	
	-- 테스트 2: Echo 100회 반복
	print("\n[TEST 2] Echo 100회 반복 호출...")
	local echoSuccess = 0
	local echoFail = 0
	startTime = os.clock()
	
	for i = 1, 100 do
		local testText = "Test_" .. i
		local ok, result = NetClient.Echo(testText)
		if ok and result and result.text == testText then
			echoSuccess += 1
		else
			echoFail += 1
			warn("[TEST 2] Echo 실패 #" .. i, ok, result)
		end
	end
	
	local echoTime = os.clock() - startTime
	print(string.format("[TEST 2] Echo 결과: %d/100 성공 (%.2f초)", echoSuccess, echoTime))
	
	if echoSuccess == 100 then
		passed += 1
		print("[TEST 2] PASSED ✓")
	else
		failed += 1
		print("[TEST 2] FAILED ✗")
	end
	
	-- 테스트 3: Unknown Command → NET_UNKNOWN_COMMAND
	print("\n[TEST 3] Unknown Command 테스트...")
	local ok, err = NetClient.Request("Invalid.Command", {})
	
	if not ok and err == "NET_UNKNOWN_COMMAND" then
		passed += 1
		print("[TEST 3] PASSED ✓ - 에러:", err)
	else
		failed += 1
		print("[TEST 3] FAILED ✗ - 예상: NET_UNKNOWN_COMMAND, 결과:", ok, err)
	end
	
	-- 테스트 4: 다른 Unknown Commands
	print("\n[TEST 4] 다양한 Unknown Commands 테스트...")
	local unknownCommands = {
		"Some.Random.Command",
		"",
		"NotExist",
	}
	
	local unknownPassed = 0
	for _, cmd in ipairs(unknownCommands) do
		local cmdOk, cmdErr = NetClient.Request(cmd, {})
		if not cmdOk and cmdErr == "NET_UNKNOWN_COMMAND" then
			unknownPassed += 1
		else
			warn("[TEST 4] 예기치 않은 결과:", cmd, cmdOk, cmdErr)
		end
	end
	
	if unknownPassed == #unknownCommands then
		passed += 1
		print("[TEST 4] PASSED ✓ - 모든 unknown command 정상 처리")
	else
		failed += 1
		print("[TEST 4] FAILED ✗")
	end
	
	-- 결과 요약
	print("\n========================================")
	print(string.format("[TEST] 완료: %d 통과, %d 실패", passed, failed))
	print("========================================")
	
	if failed == 0 then
		print("[DoD] 모든 테스트 통과! ✓")
	else
		warn("[DoD] 일부 테스트 실패 ✗")
	end
end

-- 테스트 실행
task.spawn(runTests)
