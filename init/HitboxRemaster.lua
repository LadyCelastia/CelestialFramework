--[[
	LadyCelestia 9/23/2023
	A complete overhaul of HitboxMaster. Type-safe.
--]]

--[[
    @define
    @type
    Type definitions
--]]
type enumPair<T> = {string: T}
type Pair<k,v> = {k: v}
type BezierPoints = {
	Start: Vector3,
	Control1: Vector3,
	Control2: Vector3 | nil,
	End: Vector3
}
export type ScriptConnection = {
	_Connected: boolean,
	_Signal: ScriptSignal,
	_Function: (any) -> (any),
	_Identifier: string,
	_Once: boolean,
	_State: string,
	_Fire: (any) -> (),

	new: (ScriptSignal, (any), boolean?) -> (ScriptConnection),
	StateEnum: {enumPair<string>},
	GetIdentifier: () -> (string),
	Disconnect: () -> ()
}
export type ConnectionRunner = {
	_Connections: {ScriptConnection},
	_State: string,
	_AddConnection: (ScriptConnection) -> (),
	_RemoveConnection: (string) -> (),
	_CleanUp: () -> (),
	_GetConnections: () -> (Pair<number, ScriptConnection>),
	_FireOne: (string, {any}) -> (),
	_FireAll: (any) -> (),

	new: () -> (ConnectionRunner),
	StateEnum: {enumPair<string>},
	Destroy: () -> ()
}
export type ScriptSignal = {
	_ActiveRunner: ConnectionRunner,
	_State: string,

	new: () -> (ScriptSignal),
	StateEnum: {enumPair<string>},
	Connect: ((any), boolean?) -> (ScriptConnection),
	DisconnectAll: () -> (),
	DisconnectOne: (string) -> (),
	Once: ((any)) -> (ScriptConnection),
	Fire: (any) -> (),
	FireOne: (string, {any}) -> (),
	GetState: () -> (string),
	Destroy: () -> ()
}
export type TrajectoryType = {
	_DirectionalVector: Vector3 | nil,
	_Length: number,
	_Completion: number,
	_Points: Pairs<string, Vector3>,
	_GetBezierMode: () -> (string),

	new: (Pair<string, any>) -> (TrajectoryType),
	Construct: (string, Pair<string, any>) -> (boolean),
	Deconstruct: () -> (),
	Destroy: () -> (),
	ConstructionEnum: enumPair<string>,
	BezierEnum: enumPair<string>,
	ConstructionMode: string,
	Velocity: number
}
export type HitboxType = {
	_Attachment: attachment | nil,
	_CurrentFrame: number,
	_CanWarn: boolean,
	_Visual: BasePart | nil,

	new: (Pair<string, any>) -> (HitboxType),
	Visualize: () -> (BasePart | nil),
	Unvisualize: (boolean) -> (),
	Activate: () -> (),
	Deactivate: () -> (),
	GetCurrentSerial: () -> (number),
	GetConstructionEnum: () -> (enumPair<string>),
	GetConstructionMode: () -> (string),
	GetCurrentMode: () -> (string),
	GetVelocity: () -> (number),
	SetVelocity: (number) -> (),
	AddIgnore: (Instance) -> (boolean),
	RemoveIgnore: (Instance) -> (number),
	IsHitboxBackstab: (BasePart, HitboxDataBundle) -> (boolean),
	IsBackstab: (BasePart, Model) -> (boolean),
	Destroy: () -> (),
	ShapeEnum: enumPair<string>,
	ModeEnum: enumPair<string>,
	StateEnum: enumPair<string>,
	Hit: ScriptSignal,
	Trajectory: TrajectoryType,
	Serial: number,
	Shape: string,
	Position: Vector3,
	Pierce: number,
	Debounce: number,
	LifeTime: number,
	Orientation: Vector3,
	CopyCFrame: BasePart,
	OverlapParams: OverlapParams,
	Active: boolean,
	Radius: number,
	Size: Vector3,
}
export type HitboxDataBundle = {
	Position: Vector3,
	Radius: number,
	Size: Vector3
}

--[[
    @define
    Definitions
--]]
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local DebugMode = true
local HitboxSerial = 0
local ActiveHitboxes = {}

--[[
    @function
    Universal functions
--]]
-- Debug mode for stack tracer
local function getStackLevel(): number
	if DebugMode == true then
		return 1
	end
	return 2

end

-- Concatenate string prefix for console output
local function concatPrint(String: string): string
    return "[" .. script.Name .. "]: " .. String
end

-- Find an index/value or index-value pair in Table and all its children tables
local function DeepFind(Table: {any}, Row: Pair<any, any>): Pair<any, any> | nil
    if #Row ~= 1 then
        error(concatPrint("Row argument of function DeepFind may only have one key-value pair."), getStackLevel())
    end
    for i,v in pairs(Table) do
        if typeof(v) ~= "table" then
            if Row[i] ~= nil then
                return {i = v}
            else
                for _,v2 in pairs(Row) do
                    if v == v2 then
                        return {i = v}
                    end
                end
            end
        else
            local RecursiveResult = DeepFind(v, Row)
            if RecursiveResult ~= nil then
                return RecursiveResult
            end
        end
    end
    return nil
end

-- table.remove en mass
local function CullTable(TableToCull: Pair<any, any>, CullingList: Pair<number, any>): Pair<any, any>
    for i = 1, #TableToCull do
        local target = CullingList[i]
        if TableToCull[target] then
            table.remove(TableToCull, target)
            for i2, v in ipairs(CullingList) do
                if v > target then
                    CullingList[i2] -= 1
                end
            end
        end
    end
    return TableToCull
end

-- Check if method/variable is private
local function IsPrivate(String: string): boolean
    if string.match(String, "_%a+") ~= nil then
        return true
    end
    return false
end

-- Factorized quadratic bezier equation
local function quadbez(a: LerpValue, b: LerpValue, c:LerpValue, t: number): LerpValue
    return (1 - t)^2*a + 2*(1 - t)*t*b + t^2*c
end

-- Factorized cubic bezier equation
local function cubicbez(a: LerpValue, b: LerpValue, c: LerpValue, d: LerpValue, t: number): LerpValue
    return (1 - t)^3*a + 3*(1 - t)^2*t*b + 3*(1 - t)*t^2*c + t^3+d
end

-- Return the combined length of segments
local function seglen(segments: {Vector3}): number
    local length = 0
    for i = 1, #segments do
        local current, next = segments[i], segments[i + 1]
        if not next then
            continue
        end
        length += (current - next).Magnitude
    end
    return length
end

-- Return a rough estimated total length of a quadratic bezier curve
local function quadbezlen(startPoint: Vector3, controlPoint: Vector3, endPoint: Vector3, resolution: number?): number
    resolution = resolution or 10
    local segments = {}
    for i = 1, resolution do
        table.insert(segments, quadbez(startPoint, controlPoint, endPoint, i/resolution))
    end
    return seglen(segments)
end

-- Return a rough estimated total length of a cubic bezier curve
local function cubicbezlen(startPoint: Vector3, controlPoint1: Vector3, controlPoint2: Vector3, endPoint: Vector3, resolution: number?): number
    resolution = resolution or 10
    local segments = {}
    for i = 1, resolution do
        table.insert(segments, cubicbez(startPoint, controlPoint1, controlPoint2, endPoint, i/resolution))
    end
    return seglen(segments)
end

-- Main Hitbox runner
local function UpdateHitboxes(_, deltaTime: number): ()
	for _,self in pairs(ActiveHitboxes) do
		if self.Active == true then
			self._CurrentFrame += 1
			self.LifeTime -= deltaTime
			local HitboxMode = self:GetCurrentMode()
			if HitboxMode == "Linear" then
				self.Position += (self.Trajectory._DirectionalVector * (self:GetVelocity() * deltaTime))
			elseif HitboxMode == "Bezier" then
				local interpolationGain = (self:GetVelocity() * deltaTime) / self.Trajectory._Length
				if interpolationGain > (1 - self.Trajectory._Completion) then
					interpolationGain = (1 - self.Trajectory._Completion)
				end
				self.Trajectory._Completion += interpolationGain
				self.BezierCompletion += interpolationGain
				
				if self.BezierMode == "Quadratic" then
					self.Position = quadbez(self.StartPoint, self.ControlPoint1, self.EndPoint, self.Trajectory._Completion)
				elseif self.BezierMode == "Cubic" then
					self.Position = cubicbez(self.StartPoint, self.ControlPoint1, self.ControlPoint2, self.EndPoint, self.Trajectory._Completion)
				end
			elseif HitboxMode == "Attachment" then
				self.Position = self.Attachment.WorldCFrame.Position
			end

			if self._CurrentFrame >= 5 and self._Visual ~= nil then
				self._CurrentFrame = 0
				if self.Shape == "Sphere" then
					self.Visual.Shape = Enum.PartType.Ball
					self.Visual.Size = Vector3.new(self.Radius * 2, self.Radius * 2, self.Radius * 2)
				else
					self.Visual.Shape = Enum.PartType.Block
					self.Visual.Size = self.Size
				end
				
				if self.CopyCFrame ~= nil then
					self.Visual.CFrame = self.CopyCFrame.CFrame
				elseif self.Position ~= nil then
					if self.Orientation ~= nil then
						self.Visual.CFrame = CFrame.new(self.Position) * CFrame.Angles(math.rad(self.Orientation.X), math.rad(self.Orientation.Y), math.rad(self.Orientation.Z))
					else
						self.Visual.Position = self.Position
					end
				end
			end

			if self.Pierce > 0 then
				local result: {BasePart} = {}
				if self.Shape == "Sphere" then
					result = workspace:GetPartBoundsInRadius(self.Position, self.Radius, self.OverlapParams) or {}
				elseif self.Shape == "Box" then
					if typeof(self.Orientation) == "Vector3" then
						result = workspace:GetPartBoundsInBox(CFrame.new(self.Position) * CFrame.Angles(math.rad(self.Orientation.X), math.rad(self.Orientation.Y), math.rad(self.Orientation.Z)), self.Size, self.OverlapParams) or {}
					elseif typeof(self.CopyCFrame) == "BasePart" then
						result = workspace:GetPartBoundsInBox(self.CopyCFrame.CFrame, self.Size, self.OverlapParams) or {}
					else
						result = workspace:GetPartBoundsInBox(CFrame.new(self.Position), self.Size, self.OverlapParams) or {}
					end
				elseif self._CanWarn == true then
					self._CanWarn = false
					task.delay(5, function()
						self._CanWarn = true
				    end)
					warn(concatPrint("Hitbox " .. self.Serial .. " has an invalid shape."))
				end
				if #result > 0 then
					local hitHumanoids: {humanoid: BasePart} = {}
					local registeredHumanoids: {Humanoid} = {}

					for _,v in ipairs(result) do
						local hum = v.Parent:FindFirstChildOfClass("Humanoid")
						if hum ~= nil then
							if v.Parent:FindFirstChildOfClass("ForceField") == nil and v.Parent:FindFirstChild("HitboxSerial" .. self.Serial) == nil and hum:GetState() ~= Enum.HumanoidStateType.Dead then
								table.insert(hitHumanoids, {hum, v})
							end
						end
					end

					for _,v in pairs(hitHumanoids) do
						local canHit = true
						for _,v2 in ipairs(registeredHumanoids) do
							if v[1] == v2 then
								canHit = false
								break
							end
						end
						if canHit == true then
							if self.Debounce > 0 then
								local newSerial: BoolValue = Instance.new("BoolValue")
								Debris:AddItem(newSerial, self.Debounce)
								newSerial.Name = "HitboxSerial" .. self.Serial
								newSerial.Value = true
								newSerial.Parent = v.Parent
							end
							self.Hit:Fire(v[1], v[2], {
								["Position"] = self.Position,
								["Radius"] = self.Radius or 0,
								["Size"] = self.Size or Vector3.new(0, 0, 0)
							})
							table.insert(registeredHumanoids, v[1])
							self.Pierce -= 1
							if self.Pierce <= 0 then
								break
							end
						end
					end
				end
			end
			if (self.LifeTime <= 0 and HitboxMode ~= "Bezier") or (HitboxMode == "Bezier" and self.Trajectory._Completion >= 1) then
				self:Destroy()
			end
		end
	end
end

--[[
    @class Enum
    Enumeration implementation to prevent unexpected values
--]]
local enum = {}
local enumMetatable = {
    __index = function(_, i): any
        return enum[i] or error(concatPrint(i .. " is not a valid member of the Enum."), getStackLevel())
    end,
    __newindex = function(): ()
        error(concatPrint("Enums are read-only."), getStackLevel())
    end
}

enum._new = function(Name: string, Children: {string: any}): enumPair<any>
	if enum[Name] ~= nil then
		return enum[Name]
	end

	enum[Name] = Children

	return setmetatable(Children, enumMetatable)
end

enum._get = function(Name: string): enumPair<any>
	if enum[Name] then
		return {Name = setmetatable(enum[Name], enumMetatable)}
	else
		local Result = DeepFind(enum, {Name = nil})
        if Result ~= nil then
            return setmetatable(Result, enumMetatable)
        end
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
enum._new("BezierMode", {Quadratic = "Quad", Cubic = "Cubic"})
enum._new("HitboxShape", {Box = "Box", Sphere = "Sphere"})
enum._new("HitboxMode", {None = "None", Attachment = "Attachment", Linear = "Linear", Bezier = "Bezier", Orientation = "Orientation", Copying = "Copy"})


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
	Cn._State = enum.StateEnum.Active
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

--[[
    @class Trajectory
	Child of @Hitbox
	Enables trajectory construction
--]]
local Trajectory = {}
Trajectory.__index = Trajectory
Trajectory.ConstructionEnum = enum._get("ConstructionMode")
Trajectory.BezierEnum = enum._get("BezierMode")

Trajectory.new = function(Fields: {Pair<string, any>}): TrajectoryType
	Fields = Fields or {}
	local self = setmetatable({}, Trajectory)

	self._State = enum.StateEnum.Active
	self.ConstructionMode = enum.ConstructionMode.None

	-- Linear Construction
	self._DirectionalVector = nil

	-- Bezier Construction
	self._Length = 0
	self._Completion = 0
	self._Points = {}

	-- Universal
	self.Velocity = Fields["Velocity"] or 10

	return self
end

function Trajectory:_GetBezierMode(): string
	if self._Points.Control2 == nil then
		return enum.BezierMode.Quadratic
	else
		return enum.BezierMode.Cubic
	end
end

function Trajectory:Construct(Mode: string, Fields: {Pair<string, any>}): boolean
	Fields = Fields or {}
	if Mode ~= enum.ConstructionMode.None and enum._isEnum(Mode) == true then
		if Mode == enum.ConstructionMode.Linear then
			self._DirectionalVector = Fields["DirectionalVector"] or error(concatPrint("Trajectory:Construct(Linear) is missing field DirectionalVector."), getStackLevel())
		elseif Mode == enum.ConstructionMode.Bezier then
			self._Points = Fields["BezierPoints"] or error(concatPrint("Trajectory:Construct(Bezier) is missing field BezierPoints."), getStackLevel())
			if self:_GetBezierMode() == enum.BezierMode.Quadratic then
				self._Length = quadbezlen(self._Points["Start"], self._Points["Control1"], self._Points["End"])
			else
				self._Length = cubicbezlen(self._Points["Start"], self._Points["Control1"], self._Points["Control2"], self._Points["End"])
			end
		end
		self.Velocity = Fields["Velocity"] or self.Velocity
		self.ConstructionMode = Mode
		return true
	end
	return false
end

function Trajectory:Deconstruct(): ()
	self.ConstructionMode = enum.ConstructionMode.None
	self._DirectionalVector = nil
	self._Length = 0
	self._Completion = 0
	self._Points = {}
end

function Trajectory:Destroy(): ()
	self = {_State = enum.StateEnum.Dead}
end

--[[
    @main
    @class Hitbox
    @parent enum, ScriptSignal, Trajectory
    Hitbox class
--]]
local Hitbox = {}
Hitbox.__index = Hitbox
Hitbox.ShapeEnum = enum._get("HitboxShape")
Hitbox.ModeEnum = enum._get("HitboxMode")
Hitbox.StateEnum = enum._get("StateEnum")

Hitbox.new = function(Fields: {Pair<string, any>}): HitboxType
	Fields = Fields or {}
	HitboxSerial += 1
    local self = setmetatable({}, Hitbox)

    -- Private variables
    self._Attachment = Fields["Attachment"]
	self._CurrentFrame = 0
	self._CanWarn = true
	self._Visual = nil

    -- Public variables
    self.Hit = Signal.new()
	self.Trajectory = Trajectory.new()
	self.Serial = HitboxSerial
	self.Shape = Fields["Shape"] or enum.HitboxShape.Box
	self.Position = Fields["Position"] or Vector3.new(0, 0, 0)
	self.Pierce = Fields["Pierce"] or 1
	self.Debounce = Fields["Debounce"] or 5
	self.LifeTime = Fields["LifeTime"] or 1
	self.Orientation = Fields["Orientation"]
	self.CopyCFrame = Fields["CopyCFrame"]
	self.OverlapParams = OverlapParams.new()
	self.OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self.OverlapParams.FilterDescendantsInstances = {}
	self.OverlapParams.RespectCanCollide = false
	self.OverlapParams.MaxParts = 0
	self.Active = false
	self.State = enum.StateEnum.Paused

	self.Radius = Fields["Radius"] or 3 -- Used for Sphere shape
	self.Size = Fields["Size"] or Vector3.new(3, 3, 3) -- Used for Box shape

	ActiveHitboxes[self.Serial] = self

	return self
end

function Hitbox:Visualize(): BasePart | nil
	if self._Visual ~= nil then
		warn(concatPrint("Hitbox is already visualizing."))
		return nil
	end

	self._Visual = Instance.new("Part")
	self._Visual.Name = "HitboxVisualization" .. tostring(self:GetSerial())
	self._Visual.Anchored = true
	self._Visual.CanCollide = false
	self._Visual.BrickColor = BrickColor.new("Really red")
	self._Visual.Transparency = 0.75
	self._Visual.Material = Enum.Material.SmoothPlastic
	self._Visual.Position = self.Position or Vector3.new(0, 0, 0)
	
	if self.Shape == enum.HitboxShape.Sphere then
	    self._Visual.Shape = Enum.PartType.Ball
		self._Visual.Size = Vector3.new(self.Radius * 2, self.Radius * 2, self.Radius * 2)
	else
		self._Visual.Shape = Enum.PartType.Block
		self._Visual.Size = self.Size
	end

	self._Visual.Parent = workspace
	
	return self._Visual
end

function Hitbox:Unvisualize(doNotWarn: boolean): ()
	if self._Visual == nil then
		if doNotWarn ~= true then
			warn(concatPrint("Hitbox is not visualizing."))
		end
		return false
	end
	
	self._Visual:Destroy()
	self._Visual = nil
	
	return true
end

function Hitbox:Activate(): ()
	self.Active = true
	self.State = enum.StateEnum.Active
end

function Hitbox:Deactivate(): ()
	self.Active = false
	self.State = enum.StateEnum.Paused
end

function Hitbox:GetCurrentSerial(): number
	return HitboxSerial
end

function Hitbox:GetConstructionEnum(): enumPair<string>
	return self.Trajectory.ConstructionEnum
end

function Hitbox:GetConstructionMode(): string
	return self.Trajectory.ConstructionMode
end

function Hitbox:GetCurrentMode(): string
	if self._Attachment ~= nil then
		return enum.HitboxMode.Attachment
	elseif self.Trajectory.ConstructionMode == enum.ConstructionMode.Linear then
		return enum.HitboxMode.Linear
	elseif self.Trajectory.ConstructionMode == enum.ConstructionMode.Bezier then
		return enum.HitboxMode.Bezier
	elseif self.Orientation ~= nil and self.Orientation ~= Vector3.new(0, 0, 0) then
		return enum.HitboxMode.Orientation
	elseif self.CopyCFrame ~= nil then
		return enum.HitboxMode.CopyCFrame
	else
		return enum.HitboxMode.None
	end
end

function Hitbox:GetVelocity(): number
	return self.Trajectory.Velocity
end

function Hitbox:SetVelocity(velocity: number): ()
	self.Trajectory.Velocity = velocity
end

function Hitbox:AddIgnore(object: Instance): boolean
	if typeof(object) == "Instance" then
		if object:IsA("BasePart") or object:IsA("Model") then
			self.OverlapParams.FilterDescendantsInstances = table.insert(self.OverlapParams.FilterDescendantsInstances or {}, object)
			return true
		end
	end
	return false
end

function Hitbox:RemoveIgnore(object: Instance): number
	if typeof(object) == "Instance" then
		if object:IsA("BasePart") or object:IsA("Model") then
			local indexes = {}
			for i,v in ipairs(self.OverlapParams.FilterDescendantsInstances) do
				if v == object then
					table.insert(indexes, i)
				end
			end
			for i,v in ipairs(indexes) do
				table.remove(self.OverlapParams.FilterDescendantsInstances, v)
				for i2,v2 in ipairs(indexes) do
					if i2 > i and v2 > v then
						indexes[i2] -= 1
					end
				end
			end
			return #indexes
		end
	end
	return 0
end

function Hitbox:IsHitboxBackstab(Part: BasePart, DataBundle: HitboxDataBundle): boolean
	if DataBundle.Radius > 100 or DataBundle.Size.X > 50 or DataBundle.Size.Y > 50 or DataBundle.Size.Z > 50 then
		warn(concatPrint("Hitbox is too large to support Hitbox:IsHitboxBackstab(). (Maximum 50 magnitude per-axis)"))
		return false
	elseif CFrame.new(DataBundle.Position):inverse() * Part.CFrame < 0 then
		return true
	end
	return false
end

function Hitbox:IsBackstab(Part: BasePart, Character: Model): boolean
	local root: BasePart = Character:FindFirstChild("HumanoidRootPart")
    if root then
		if root.CFrame:inverse() * Part.CFrame < 0 then
			return true
		end
	end
	warn(concatPrint("Provided Character for Hitbox:IsBackstab() has no HumanoidRootPart."))
	return false
end

function Hitbox:Destroy(): ()
	self:Deactivate()
	self.Hit:DisconnectAll()
	self.Hit:Destroy()
	self.Trajectory:Destroy()
	self:Unvisualize()
	ActiveHitboxes[self.Serial] = nil
	self = {State = enum.StateEnum.Dead}
end

RunService.Stepped:Connect(UpdateHitboxes)

return Hitbox
