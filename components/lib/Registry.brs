' Persisted state via roRegistry. TV_APP_SPEC §11.
' Roku has no separate "secure" store; the registry is per-channel and
' sandboxed, which is the platform-standard place for the bearer token.

function RegRead(key as string) as dynamic
    cfg = ReversionConfig()
    sec = CreateObject("roRegistrySection", cfg.REGISTRY_SECTION)
    if sec.Exists(key) then
        return sec.Read(key)
    end if
    return invalid
end function

sub RegWrite(key as string, value as string)
    cfg = ReversionConfig()
    sec = CreateObject("roRegistrySection", cfg.REGISTRY_SECTION)
    sec.Write(key, value)
    sec.Flush()
end sub

sub RegDelete(key as string)
    cfg = ReversionConfig()
    sec = CreateObject("roRegistrySection", cfg.REGISTRY_SECTION)
    if sec.Exists(key) then
        sec.Delete(key)
        sec.Flush()
    end if
end sub

function GetAuthToken() as dynamic
    return RegRead(ReversionConfig().KEY_AUTH_TOKEN)
end function

sub SaveAuthToken(token as string)
    RegWrite(ReversionConfig().KEY_AUTH_TOKEN, token)
end sub

' Wipe token (sign out / 401). §2, §5.
sub ClearAuthToken()
    RegDelete(ReversionConfig().KEY_AUTH_TOKEN)
end sub
