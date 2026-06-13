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
        else if msgType = "roSGNodeEvent" then
            if msg.getField() = "exitApp" and msg.getData() = true then
                screen.close()
                return
            end if
        end if
    end while
end sub
