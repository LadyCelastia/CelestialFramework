--[[
    @class Enum
    Enumeration implementation to prevent unexpected values
--]]
local enum = {}

enum._new = function(Name: string, Children: {string: any}): enumPair<any>
	if enum[Name] ~= nil then
		return enum[Name]
	end

	enum[Name] = Children

	return setmetatable(Children, {
		__index = function(_, i): any
			return enum[i] or error(concatPrint(i .. " is not a valid member of the Enum."), getStackLevel())
		end,
		__newindex = function(): ()
			error(concatPrint("Enums are read-only."), getStackLevel())
		end
	})
end

enum._get = function(Name: string): enumPair<any>
	if enum[Name] then
		return {Name = enum[Name]}
	else
		return DeepFind(enum, {Name = nil})
	end
end

-- Do not call _isEnum as a method as self is readonly
enum._isEnum = function(ValueToCheck: any): boolean
	if IsPrivate(ValueToCheck) == false and DeepFind(enum, {ValueToCheck}) ~= nil then
		return true
	end
	return false
end

enum._new("StateEnum", {Active = "Active", Paused = "Paused", Dead = "Dead"})
enum._new("ConstructionMode", {None = nil, Linear = "Linear", Bezier = "Bezier"})

--[[
    @class ScriptConnection
    Child of @ConnectionRunner
--]]
local Connection = {}
Connection.__index = Connection
Connection.StateEnum = enum._get("StateEnum")

Connection.new = function(signal: ScriptSignal, func: any, once: boolean?): ScriptConnection
	local self = setmetatable({}, Connection)

	self._Connected = true
	self._Signal = signal
	self._Function = func
	self._Identifier = HttpService:GenerateGUID(false)
	self._Once = false
	if once ~= nil then
		self._Once = once
	end
	self._State = enum.StateEnum.Paused

	return self
end

function Connection:_Fire(...): ()
	if self._Connected == true then
		coroutine.wrap(self._Function)(...)
		if self._Once == true then
			self:Disconnect()
		end
	end
end

function Connection:GetIdentifier(): string
	return self._Identifier
end

function Connection:Disconnect(): ()
	self._Connected = false
	self._Function = nil
	self = {_State = enum.StateEnum.Dead}
end

--[[
    @class ConnectionRunner
    @parent ScriptConnection
    Private child of @ScriptSignal, manages child ScriptConnections
--]]
local Runner = {}
Runner.__index = Runner
Runner.StateEnum = enum._get("StateEnum")

Runner.new = function(): ConnectionRunner
	local self = setmetatable({}, Runner)

	self._Connections = {}
	self._State = enum.StateEnum.Active

	return self
end

function Runner:_AddConnection(Cn: ScriptConnection): ()
	table.insert(self._Connections, Cn)
end

function Runner:_CleanUp(): ()
	local CullingList = {}
	for i,v in ipairs(self._Connections) do
		if v._Connected == false then
			table.insert(CullingList, i)
		end
	end
	CullTable(self._Connections, CullingList)
end

function Runner:_RemoveConnection(identifier: string): ()
	for _,v in ipairs(self._Connections) do
		if v._Identifier == identifier then
			v:Disconnect()
		end
	end
	self:_CleanUp()
end

function Runner:_GetConnections(): Pair<number, ScriptConnection>
	return self._Connections
end

function Runner:_FireOne(identifier: string, args: {any}): ()
	for _,v in ipairs(self._Connections) do
		if v._Identifier == identifier then
			v:Fire(table.unpack(args))
		end
	end
end

function Runner:_FireAll(...): ()
	for _,v in ipairs(self._Connections) do
		v:_Fire(...)
	end
end

function Runner:Destroy(): ()
	for _,v in ipairs(self._Connections) do
		v:Disconnect()
	end
	self:_CleanUp()
	self = {_State = enum}
end

--[[
    @class ScriptSignal
    @parent enum, ConnectionRunner
    ScriptSignal implementation
--]]
local Signal = {}
Signal.__index = Signal
Signal.StateEnum = enum._get("StateEnum")

Signal.new = function(): ScriptSignal
	local self = setmetatable({}, Signal)

	self._ActiveRunner = Runner.new()
	self._State = enum.StateEnum.Active

	return self
end

function Signal:GetState(): string
	return self._State
end

function Signal:FireOne(...): ()
	self._ActiveRunner:_FireOne(...)
end

function Signal:Fire(...): ()
	self._ActiveRunner:_FireAll(...)
end

function Signal:Connect(func: any, connectImmediately: boolean?): ScriptConnection
	if connectImmediately == nil then
		connectImmediately = true
	end
	local newConnection = Connection.new(self, func)

	if connectImmediately == true then
		self._ActiveRunner:_AddConnection(newConnection) 
	end

	return newConnection
end

function Signal:DisconnectOne(identifier: string): ()
	self._ActiveRunner:_RemoveConnection(identifier)
end

function Signal:DisconnectAll(): ()
	for _,v in ipairs(self._ActiveRunner:_GetConnections()) do
		v:Disconnect()
	end
	self._ActiveRunner:_CleanUp()
end

function Signal:Once(func: any): ScriptConnection
	local newConnection = self:Connect(func, false)
	newConnection._Once = true

	self._ActiveRunner:_AddConnection(newConnection)

	return newConnection
end

function Signal:Destroy(): ()
	self:DisconnectAll()
	self._ActiveRunner:Destroy()
	self = {_State = enum.StateEnum.Dead}
end
