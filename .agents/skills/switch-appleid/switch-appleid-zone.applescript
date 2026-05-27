#!/usr/bin/osascript

# Switch macOS App Store Apple ID by region.
# Credentials read from Keychain (service: AppleId_CN/US/TU).
# Usage: osascript switch-appleid-zone.applescript <cn|us|tu>

on run argv
	# ------------------ step 1: 解析参数 & 本地化菜单名 ------------------

	# zone: cn=国区, us=美区, tu=土耳其区（可自行扩展）
	set zone to item 1 of argv

	set lang to user locale of (get system info)

	# 目前只适配简体中文 (zh_CN) 和英文 (en_*)。其他语言下 App Store 的菜单文案不同，
	# 直接报错让用户感知，比按英文菜单猜要安全。新增语言：加一个 else if 分支即可。
	if lang is equal to "zh_CN" then
		set signInMenuItem to "登录"
		set signOutMenuItem to "退出登录"
		set menuNameOfStore to "商店"
	else if lang starts with "en" then
		set signInMenuItem to "Sign In"
		set signOutMenuItem to "Sign Out"
		set menuNameOfStore to "Store"
	else
		error "不支持的系统语言：" & lang & "。当前脚本仅适配 zh_CN 与 en_*（英文）。请在「系统设置 → 通用 → 语言与地区」临时切到简体中文或英文后重试，或自行在脚本里追加 else if 分支。"
	end if

	# 把 zone 映射到钥匙串 service 名。新增区域只需加 else if + 在钥匙串里加条目。
	if zone is equal to "cn" then
		set theService to "AppleId_CN"
	else if zone is equal to "us" then
		set theService to "AppleId_US"
	else if zone is equal to "tu" then
		set theService to "AppleId_TU"
	else
		error "未知的 zone：" & zone & "，请使用 cn / us / tu"
	end if

	set creds to getKeychainCredentials(theService)
	set account to account of creds
	set pwd to password of creds

	# ------------------ step 2: 重启 App Store ------------------
	# 已启动的话先 quit，避免商店菜单按钮灰着点不动

	tell application "System Events"
		if exists process "App Store" then
			set isRunning to true
		else
			set isRunning to false
		end if
	end tell

	if isRunning then
		tell application "App Store"
			quit
		end tell
		delay 2
	end if

	activate application "App Store"
	tell application "System Events"
		tell process "App Store"
			set frontmost to true
			delay 2 -- 等待 App Store 完全加载

			# ------------------ step 3: 打开商店菜单，唤出登录弹窗 ------------------

			click menu bar item menuNameOfStore of menu bar 1
			delay 2

			if exists (menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1) then
				# 当前未登录
				click menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
			else
				# 已登录：先退出再点登录
				click menu item signOutMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
				delay 5
				click menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
			end if
			delay 2

			# ------------------ step 4: 输入账号 & 密码 ------------------

			# 先输账号 → 回车进入密码界面
			set value of text field 1 of sheet 1 of sheet 1 of window 1 to account
			keystroke return
			delay 2

			# 坑点：切到下一步后，账号变成 text field 2，密码是 text field 1
			set value of text field 2 of sheet 1 of sheet 1 of window 1 to account
			set value of text field 1 of sheet 1 of sheet 1 of window 1 to pwd
			keystroke return

			# ------------------ step 5: 两步验证需用户手动完成 ------------------

		end tell
	end tell
end run

# 从钥匙串读取账号和密码，service 名约定为 AppleId_<REGION>
on getKeychainCredentials(theService)
	try
		set theAccount to do shell script ¬
			"security find-generic-password -s " & quoted form of theService & ¬
			" | awk -F'\"' '/acct/{print $4}'"

		set thePassword to do shell script ¬
			"security find-generic-password -s " & quoted form of theService & " -w"

		return {account:theAccount, password:thePassword}
	on error errMsg number errNum
		error "读取钥匙串失败 (" & theService & "): " & errMsg number errNum
	end try
end getKeychainCredentials
