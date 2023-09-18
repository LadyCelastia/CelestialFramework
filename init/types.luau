local module = {}

export type ScriptSignal = {
    Connect: "function",
    DisconnectAll: "function",
    Fire: "function",
    Wait: "function",
    Once: "function",
}

export type ScriptConnection = {
    Disconnect: "function",
}

return module