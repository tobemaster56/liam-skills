-- switch-appleid-zone.applescript —— 切换登录不同地区的 Mac App Store 账号
--
-- 用法:
--   osascript switch-appleid-zone.applescript cn      登录国区
--   osascript switch-appleid-zone.applescript us      登录美区
--   osascript switch-appleid-zone.applescript tu      登录土区
--
-- 实现:现代 macOS 没有官方命令行能登录 App Store(mas 的 signin 已被废弃),
--   本脚本通过 accessibility(辅助功能)直接定位 App Store 登录对话框里的
--   「Apple ID 文本框 / 密码框 / Sign In 按钮」并操作,不依赖屏幕坐标,较稳定。
--   登录分两步:先填 Apple ID 回车,出现密码框后再填密码回车提交。
--
-- 前置条件:
--   1) 「钥匙串访问」里为每个地区建了一个「密码项目」:
--        名称 = 下方 keychainItemFor 里填的字符串
--        账户 = 你的 Apple ID 邮箱
--        密码 = 该 Apple ID 的密码
--   2) 已给「终端」(或运行此脚本的程序)授予「辅助功能」权限:
--        系统设置 → 隐私与安全性 → 辅助功能 → 勾选 终端/iTerm。
--   3) 账号未开启双重认证(2FA);若开启,填完密码后需手动输入验证码。

-- ── 配置:把返回值改成你钥匙串里「名称」列显示的真实名字 ──
on keychainItemFor(region)
	if region is "cn" then return "AppleId_CN"   -- 国区
	if region is "us" then return "AppleId_US"   -- 美区
	if region is "tu" then return "AppleId_TU"   -- 土区
	return missing value
end keychainItemFor

-- ── 按系统语言返回菜单项名称:{商店菜单, 登录, 退出登录} ──
--   未知语言默认英文。返回的名字会再配合省略号/跨语言兜底使用。
on localeMenuNames()
	set lang to ""
	try
		set lang to do shell script "defaults read -g AppleLocale 2>/dev/null"
	end try
	if lang is "" then
		try
			set lang to user locale of (system info)
		end try
	end if
	if lang is equal to "zh_CN" or lang starts with "zh" then
		return {"商店", "登录", "退出登录"}
	else
		-- 英文及其它语言:默认按英文界面处理
		return {"Store", "Sign In", "Sign Out"}
	end if
end localeMenuNames

-- ── 把 App Store 提到最前(frontmost 偶发 -10006,容错处理)──
on ensureFront()
	tell application "App Store" to activate
	tell application "System Events" to tell process "App Store"
		try
			set frontmost to true
		end try
	end tell
end ensureFront

-- ── 探测登录 sheet:返回基本类型(不返回元素引用,避免跨 tell 失效)──
--   {hasSheet, useInner, idIdx, secIdx}
--   useInner: 控件是否在嵌套的 UI element 1(AXSheet)里
--   idIdx   : Apple ID 文本框的序号(0=无)
--   secIdx  : 密码框(secure text field)的序号(0=无)
on probeSheet()
	tell application "System Events" to tell process "App Store"
		-- 整段容错:对话框可能在探测过程中正好关闭(登录成功),
		-- 此时各种 sheet 1 访问会抛 Invalid index,统一当作「无对话框」处理。
		try
			if (count of sheets of window 1) is 0 then return {false, false, 0, 0}
			set useInner to false
			try
				if (count of text fields of (UI element 1 of sheet 1 of window 1)) > 0 then set useInner to true
			end try
			if useInner then
				set cont to UI element 1 of sheet 1 of window 1
			else
				set cont to sheet 1 of window 1
			end if
			set idIdx to 0
			set secIdx to 0
			set i to 0
			repeat with tf in text fields of cont
				set i to i + 1
				if (description of tf as text) is "secure text field" then
					set secIdx to i
				else
					set idIdx to i
				end if
			end repeat
			return {true, useInner, idIdx, secIdx}
		on error
			return {false, false, 0, 0}
		end try
	end tell
end probeSheet

-- ── 在指定文本框里输入文本并(可选)回车提交(全部内联,引用不跨块)──
--   submit: 输入后按 Return 提交。注意:实测「点 Sign In 按钮」会提交未 commit
--   的旧值导致不前进,而在字段内按 Return 会先 commit 再提交,可靠得多。
on typeInField(useInner, idx, txt, doSelectAll, submit)
	my ensureFront()
	tell application "System Events" to tell process "App Store"
		if useInner then
			set cont to UI element 1 of sheet 1 of window 1
		else
			set cont to sheet 1 of window 1
		end if
		set tf to text field idx of cont
		set focused of tf to true
		delay 0.3
		if doSelectAll then
			keystroke "a" using command down
			delay 0.2
		end if
		keystroke txt
		delay 0.3
		if submit then
			key code 36 -- Return 提交
			delay 0.3
		end if
	end tell
end typeInField

on run argv
	-- ── 解析参数 ──
	if (count of argv) < 1 then
		error "用法: osascript appstore-login.applescript <cn|us|tu>"
	end if
	set region to item 1 of argv
	set itemName to keychainItemFor(region)
	if itemName is missing value then
		error "未知地区「" & region & "」,可用: cn / us / tu"
	end if

	-- ── 从钥匙串读取邮箱(账户)与密码 ──
	set theEmail to ""
	set thePassword to ""
	try
		set theEmail to do shell script ¬
			"security find-generic-password -s " & quoted form of itemName & ¬
			" 2>/dev/null | sed -n 's/.*\\\"acct\\\"<blob>=\\\"\\(.*\\)\\\"/\\1/p'"
		set thePassword to do shell script ¬
			"security find-generic-password -s " & quoted form of itemName & " -w 2>/dev/null"
	end try
	if theEmail is "" or thePassword is "" then
		error "在钥匙串里找不到名称为「" & itemName & "」的条目(或缺少账户/密码)。" & ¬
			"请确认其「名称」与脚本中 keychainItemFor 的值完全一致。"
	end if

	log "▸ 准备登录 [" & region & "]:" & theEmail

	tell application "App Store" to activate
	delay 1.5

	-- ── 1) 菜单:已登录则先退出,再点 Sign In ──
	-- 按系统语言决定菜单名,并加省略号兜底(部分版本菜单项带 …)
	set nm0 to my localeMenuNames()
	set storeName to item 1 of nm0
	set signInName to item 2 of nm0
	set signOutName to item 3 of nm0
	set signInCands to {signInName, signInName & "…", signInName & "..."}
	set signOutCands to {signOutName, signOutName & "…"}

	my ensureFront()
	delay 1.5
	tell application "System Events" to tell process "App Store"
		-- 清理上一次可能残留的对话框,避免连锁出错
		repeat 3 times
			if (count of sheets of window 1) is 0 then exit repeat
			key code 53 -- Esc
			delay 0.5
		end repeat

		set storeMenu to missing value
		repeat with mbi in menu bar items of menu bar 1
			if (name of mbi) is storeName then
				set storeMenu to mbi
				exit repeat
			end if
		end repeat
		if storeMenu is missing value then error "找不到「" & storeName & "」菜单"

		click storeMenu
		delay 0.5
		set didSignOut to false
		repeat with nm in signOutCands
			try
				click menu item nm of menu 1 of storeMenu
				set didSignOut to true
				exit repeat
			end try
		end repeat
		if didSignOut then
			delay 2
		else
			key code 53
		end if
		delay 0.5

		click storeMenu
		delay 0.5
		set clickedSignIn to false
		repeat with nm in signInCands
			try
				click menu item nm of menu 1 of storeMenu
				set clickedSignIn to true
				exit repeat
			end try
		end repeat
		if not clickedSignIn then
			key code 53
			error "找不到「" & signInName & "」菜单项"
		end if
	end tell

	-- ── 2) 等登录 sheet 出现 ──
	set p to {false, false, 0, 0}
	repeat 20 times
		delay 0.5
		set p to my probeSheet()
		if item 1 of p then exit repeat
	end repeat
	if not (item 1 of p) then error "登录对话框未出现"
	delay 0.8
	set p to my probeSheet()

	set useInner to item 2 of p
	set idIdx to item 3 of p
	set secIdx to item 4 of p

	-- ── 3) 第一步:若有可编辑 Apple ID 框,改写为目标邮箱 ──
	if idIdx > 0 then
		if secIdx is 0 then
			-- 账号录入形态:改写邮箱 + 回车提交,等密码框出现
			my typeInField(useInner, idIdx, theEmail, true, true)
			repeat 20 times
				delay 0.5
				set p to my probeSheet()
				if (item 1 of p) and (item 4 of p) > 0 then exit repeat
			end repeat
			if not ((item 1 of p) and (item 4 of p) > 0) then ¬
				error "提交账号后未出现密码框(账号可能有误)"
		else
			-- 已是「邮箱+密码」双框:只改邮箱,不提交
			my typeInField(useInner, idIdx, theEmail, true, false)
			set p to my probeSheet()
		end if
	end if
	-- 否则:仅密码框(系统已记住该邮箱),直接填密码

	set useInner to item 2 of p
	set secIdx to item 4 of p
	if secIdx is 0 then error "未找到密码框"

	-- ── 4) 第二步:填密码 + 回车提交 ──
	my typeInField(useInner, secIdx, thePassword, false, true)

	-- ── 5) 等对话框关闭,确认登录(放宽到 ~20 秒,容忍慢网络验证)──
	set closed to false
	repeat 40 times
		delay 0.5
		set p to my probeSheet()
		if not (item 1 of p) then
			set closed to true
			exit repeat
		end if
	end repeat

	if closed then
		log "✓ [" & region & "] 登录完成:" & theEmail
	else
		log "⚠ 对话框仍未关闭,可能需要手动确认(如条款、安全验证)。"
	end if
end run
