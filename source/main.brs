' Reversion TV — Roku port
' Entry point. Spins up the SceneGraph screen and runs MainScene, which
' owns the auth gate (token -> Home, no token -> Pairing) per TV_APP_SPEC §2.

sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    ' Deep linking on launch (cert RP 5.x). Roku Search / voice / home banners
    ' launch us with contentId + mediaType; forward them so MainScene can route
    ' into content once authenticated. Invalid/empty args just land on Home.
    if args <> invalid then
        scene.setField("launchArgs", args)
    end if

    ' roInput delivers deep links WHILE we're already running (e.g. "Play X"
    ' by voice with the channel in the foreground) without relaunching. Requires
    ' supports_input_launch=1 in the manifest. cert RP 5.x.
    input = CreateObject("roInput")
    input.setMessagePort(port)

    ' Memory monitoring (cert Monitoring requirements). Prefer the cgroup-based
    ' roAppMemoryMonitor (threshold warnings + per-app limits); fall back to the
    ' older roDeviceInfo low-general-memory event on devices that lack it. Both
    ' feed our shared port; the loop below reacts to the notifications.
    memMon = CreateObject("roAppMemoryMonitor")
    usingMemMon = false
    if memMon <> invalid then
        memMon.setMessagePort(port)
        usingMemMon = memMon.EnableMemoryWarningEvent(true)
        ' Exercise the query APIs (useful for debugging headroom, and required
        ' by the cert Monitoring checks): per-app limit, free estimate, usage %.
        limits = memMon.GetChannelMemoryLimit()
        availKb = memMon.GetChannelAvailableMemory()
        usagePct = memMon.GetMemoryLimitPercent()
        if limits <> invalid then print "[mem] limit="; limits; " availKb="; availKb; " usage%="; usagePct
    end if
    devInfo = CreateObject("roDeviceInfo")
    devInfo.setMessagePort(port)
    if not usingMemMon then devInfo.EnableLowGeneralMemoryEvent(true)

    ' The exit-confirmation overlay (§6.7) sets this when the user picks Exit;
    ' closing the screen ends the channel (Roku has no direct quit API).
    scene.observeField("exitApp", port)

    while true
        msg = wait(0, port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent" then
            if msg.isScreenClosed() then return
        else if msgType = "roInputEvent" then
            if msg.isInput() then
                info = msg.getInfo()
                if info <> invalid then scene.setField("inputArgs", info)
            end if
        else if msgType = "roAppMemoryNotificationEvent" then
            ' Usage crossed a threshold (80/85/90/95%). We hold little reclaimable
            ' cache, so just log; the OS throttles these. cert Monitoring.
            print "[mem] usage% ="; msg.getInfo().lookup("MemoryUsagePercent")
        else if msgType = "roDeviceInfoEvent" then
            mi = msg.getInfo()
            if mi <> invalid and mi.generalMemoryLevel <> invalid then
                print "[mem] generalMemoryLevel ="; mi.generalMemoryLevel
            end if
        else if msgType = "roSGNodeEvent" then
            if msg.getField() = "exitApp" and msg.getData() = true then
                screen.close()
                return
            end if
        end if
    end while
end sub
