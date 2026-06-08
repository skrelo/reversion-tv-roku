' Reversion TV — Roku port
' Entry point. Spins up the SceneGraph screen and runs MainScene, which
' owns the auth gate (token -> Home, no token -> Pairing) per TV_APP_SPEC §2.

sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.setMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.show()

    ' Forward launch args (e.g. deep links) to the scene for later use.
    if args <> invalid then
        scene.launchArgs = args
    end if

    ' The exit-confirmation overlay (§6.7) sets this when the user picks Exit;
    ' closing the screen ends the channel (Roku has no direct quit API).
    scene.observeField("exitApp", port)

    while true
        msg = wait(0, port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent" then
            if msg.isScreenClosed() then return
        else if msgType = "roSGNodeEvent" then
            if msg.getField() = "exitApp" and msg.getData() = true then
                screen.close()
                return
            end if
        end if
    end while
end sub
