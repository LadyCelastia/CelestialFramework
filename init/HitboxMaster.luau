--[[
    LadyCelestia - 8/20/2023
    All-purpose calculation-based arbitrary hitbox system
--]]

local RunService = game:GetService("RunService")
if RunService:IsClient() == true then
	error("[Hitbox]: You cannot run HitboxMaster on client-side. This module supports server-side only.")
	return nil
end

local Hitbox = {}
Hitbox.__index = Hitbox

local Debris = game:GetService("Debris")

local ServerStorage = game:GetService("ServerStorage")
local Values = ServerStorage:WaitForChild("Values")
local HitboxSerial = Values:WaitForChild("HitboxSerial")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ScriptSignal = require(Modules:WaitForChild("ScriptSignal"))
local CustomGlobals = require(Modules:WaitForChild("CustomGlobals"))
local math, string, table = CustomGlobals()

local function CheckAtPos(self)
	if self.Shape == "Sphere" then
		return workspace:GetPartBoundsInRadius(self.Position, self.Radius, self.OverlapParams) or {}
	elseif self.Shape == "Box" then
		if self.Orientation ~= nil then
			return workspace:GetPartBoundsInBox(CFrame.new(self.Position) * CFrame.Angles(math.rad(self.Orientation.X), math.rad(self.Orientation.Y), math.rad(self.Orientation.Z)), self.Size, self.OverlapParams) or {}
		elseif self.CopyCFrame ~= nil then
			return workspace:GetPartBoundsInBox(self.CopyCFrame.CFrame, self.Size, self.OverlapParams) or {}
		else
			return workspace:GetPartBoundsInBox(CFrame(self.Position), self.Size, self.OverlapParams) or {}
		end
	else
		return false
	end
end

Hitbox.new = function(attachment: Attachment)
	--[[
	    Creates a Hitbox object that exists in an arbitrary euclidean space
	    
	    
	    
	    Module.new(instance or nil Attachment) - Create a new Hitbox object. Returns Hitbox.
	    Module:IsHitboxBackstab(Part, HitboxDataBundle) - Determine if the instant hitbox data described by HitboxDataBundle is a 'backstab' against Part. Returns Boolean.
	    Module:IsBackstab(Part, Character) - Determine if Character is in a position to 'backstab' Part. Returns Boolean.
	    
	    ---------[Methods]---------
	    
	    Hitbox:ChangeAttachment(instance Attachment) - Change the Attachment of the Hitbox. If Hitbox is bound to a valid Attachment afterward, return true. Otherwise return false. Leave argument empty if you want the Hitbox to be unbound.
	    Hitbox:ChangeOverlapParams(tuple Parameters) - Change the properties of OverlapParams used in Region3 scanning. Refer to Roblox API. Returns boolean Success.
	    Hitbox:AddIgnore(instance Part or Model) - Add an object to OverlapParams' IgnoreList. Returns boolean Success.
	    Hitbox:RemoveIgnore(instance Part or Model) - Remove an object from OverlapParams' IgnoreList. Returns integer RemovedAmount.
	    Hitbox:Destroy() - Completely erase the Hitbox object, halts all its operations, stop visualization and disconnect all its ScriptConnections. Hitbox becomes an empty table {}. Residue data will be unaccessible and will be garbage collected shortly. Returns boolean Success.
	    Hitbox:Visualize() - Visualize the Hitbox in transparent red. Visualization updates every 5 frames (can be wobbly). POORLY OPTIMIZED, STRICTLY FOR TESTING USES ONLY!
	    Hitbox:Unvisualize() - Unvisualize the Hitbox.
	    
	    
	    ---------[Wrapper Methods]---------
	    Wrapper methods for composition OOP.
	    
	    Hitbox:Activate() - Activate Hitbox's hit scanning.
	    Hitbox:Deactivate() - Deactivate Hitbox's hit scanning.
	    Hitbox:IsActive() - Get whether the Hitbox is active or not. Returns Boolean.
	    Hitbox:IsConstructed() - Get whether the Hitbox is constructed or not. Returns Boolean.
	    Hitbox:IsAttachment() - Get whether the Hitbox is using Attachment mode or not. Returns Boolean.
	    Hitbox:GetSerial() - Get the Serial number of this Hitbox. Returns Integer.
	    Hitbox:GetCurrentSerial() - Get the current highest Serial number of all Hitboxes. Returns Integer.
	    Hitbox:GetDebounce() - Get the Debounce of the Hitbox. Returns Integer.
	    Hitbox:GetMode() - Get the mode of the Hitbox's construction. Returns String or nil.
	    
	    
	    ---------[Construction methods]---------
	    
	    Hitbox:Disconnect() - Disconnects Hitbox.Connection. Return boolean Success.
	    Hitbox:DisconnectHit() - Disconnects all Hitbox.Hit ScriptConnections. Return boolean Success.
	    Hitbox:ConstructLinear({
	        number Velocity, - Studs per Second. Required.
	        vector3 Unit, - Directional vector of the path. Required.
	        vector3 Position, - Can be used in place of Unit (if unit is nil), second position to calculate the Unit from. Required if Unit is nil.
	        tuple IgnoreList, - A list of parts that are to be ignored by the Hitbox. Default {}
	        boolean RespectCanCollide, - If true, parts that are CanCollide == false are ignored by the Hitbox. Default false.
	        integer MaxParts, - How many parts can be scanned by the Hitbox each frame. Default infinite.
	        string CollisionGroup, - If not nil, only parts in the selected CollisionGroup are not ignored by the Hitbox. Default nil.
	    }) - Sets Mode to Linear and construct a linear trajectory for the Hitbox. Return boolean Success.
	    
	    Hitbox:ConstructBezier({
	        string Mode, - Quadratic or Cubic. Algorithm of the curve. Required.
	        number Velocity, - Studs per Second. Required.
	        vector3 Start, - Start point of the curve. Required.
	        vector3 End, - End point of the curve. Required.
	        vector3 Control1, - Control point of the curve. Required.
	        vector3 Control2, - Control point of the curve. Required if Cubic mode.
	    }) - Return boolean Success.
	    
	    Hitbox:Deconstruct(boolean Bypass) - Only usable if Active == false. Deconstruct all Hitbox trajectories (if any), allowing construction of new trajectories. Does not reset Attachment usage. If Bypass is true, deconstruct regardless of limitations. Return boolean Success.
	    
	    
	    ---------[Editable Variables]---------
	    
	    External Variables (Can be changed by other scripts)
	    -=[+++]=-
	    Hitbox.Active (Boolean) - Whether the Hitbox is active. True means the Hitbox can detect hits, false is otherwise. Default false.
	    When Hitbox is Active, its Position will move based on its constructed trajectory and mode. If there is no construction, the Hitbox will stay still.
	    If UseAttachment is true, Attachment mode will be active if Hitbox is activated while no trajectory is constructed. The Hitbox's position will snap to the position of the adorned Attachment each frame in Attachment mode.
	    Every frame while the Hitbox is Active, deltaTime of each server frame (Stepped) will be subtracted from Time.
	    
	    Hitbox.Position (Vector3) - The current location of the Hitbox. You would want to set it to your desired starting point for Linear and Bezier mode. Default Vector3.new(0, 0, 0)
	    Hitbox.Shape (String - Sphere or Box) - The shape of the Hitbox. Sphere uses Radius. Box uses Size. Default Sphere.
	    Hitbox.Radius (Integer) - How big the Hitbox is in stud. Spherical radius. Applies only when shape is Sphere. Default 3.
	    Hitbox.Size (Vector3) - The dimension of the Hitbox in Vector3. Applies only when shape is Box. Default Vector3.new(3, 3, 3).
	    Hitbox.Orientation (Vector3) - An optional orientation added to the Hitbox if Hitbox.Shape is Box. Takes priority. Overrides default.
	    Hitbox.CopyCFrame (BasePart) - An optional part whose positional CFrame is copied by the Hitbox if Hitbox.Shape is Box. Takes second priority. Overrides default.
	    Hitbox.Pierce (Integer) - How many targets can be hit in total by the Hitbox. Default 1.
	    Hitbox.Debounce (Integer) - How many seconds of immunity to this Hitbox are given to Humanoids hit. Default 5.
	    Hitbox.Time (Number) - How much lifespan the Hitbox has left before despawning in seconds. Default 1.
	    When Time hits <= 0, the Hitbox despawns and all its Hit connections disconnect as well as its RunService connection. The Hitbox object is rendered dead and should not be referenced anymore in order to be queued for Garbage Collection.
	    If Hitbox.Mode is Bezier, the Hitbox will not despawn when Time hits <= 0. Instead, the Hitbox despawns when its Bezier trajectory is traversed.
	    
	    
	    ---------[ScriptSignal]---------
	    
	    Hitbox.Hit - A ScriptSignal that can be connected to.
	    Hitbox.Hit:Connect(function(Humanoid, HitPart, HitboxDataBundle)) - Creates a ScriptConnection that's fired everytime a valid hit is registered by the Hitbox. Returns ScriptConnection.
	    Example:
	    local ScriptConnection = Hitbox.Hit:Connect(function(Humanoid, HitPart, HitboxDataBundle)
	        print(Humanoid.Parent.Name .. " has been hit!")
	        if Module:IsHitboxBackstab(HitPart, HitboxDataBundle) == true then
	            print("It is a backstab!")
	            Humanoid:TakeDamage(15)
	        else
	            Humanoid:TakeDamage(10)
	        end
	    end)
	    pcall(function()
	        ScriptConnection:Disconnect()
	    end)
	    
	    class HitboxDataBundle - A class returned by Hitbox.Hit, used for Module:IsHitboxBackstab(Part, HitboxDataBundle).
	    
	    ALWAYS wrap ScriptConnection:Disconnect() inside a pcall, as DisconnectHit, Hitbox:Deconstruct() and Hitbox:Destroy() will disconnect all ScriptConnections.
	    
	    
	    ---------[Internal Variables]---------
	    
	    Internal Variables (Do not change with other scripts)
	    -=[+++]=-
	    Hitbox.Serial (Integer) - A numeral identifier of the hitbox. Doesn't need to be changed.
	    Hitbox.Constructed (Boolean) - An internal indicator to if there is a path constructed for the Hitbox.
	    Hitbox.UseAttachment (Boolean) - Internal indicator whether an attachment is used or not.
	    Hitbox.Attachment (Instance) - The adorned Attachment.
	    Hitbox.Mode (String) - The construction mode of the Hitbox.
	    Modes:
	    Linear - Goes in a straight line based on an Unit at a constant Velocity.
	    Bezier - Goes in a curve based on Bezier Points and a Bezier Equation at a constant Velocity. Hitbox doesn't despawn when running out of time, but despawns when its Bezier trajectory is traversed.
	    Attachment - The position of the adorned Attachment is the position of the Hitbox.
	    
	    Hitbox.Signal (RBXScriptSignal) - The RunService signal that is connected to.
	    Hitbox.Connection (RBXScriptConnection) - The RunService connection that runs every server frame.
	    
	    
	    Linear Mode Variables (Internal)
	    -=[+++]=-
	    Hitbox.Unit (Vector3) - A directional vector.
	    Hitbox.Velocity (Number) - How fast the Hitbox travels in Studs per Second.
	    Hitbox.OverlapParams (OverlapParams) - OverlapParams for Region3 scanning.
	    
	    
	    Bezier Mode Variables (Internal)
	    -=[+++]=-
	    Hitbox.BezierMode (String) - Quadratic or Cubic algorithm.
	    Hitbox.BezierLength (Number) - Approximate length of the curve in studs.
	    Hitbox.Velocity (Number) - How fast the Hitbox travels in Studs per Second.
	    Hitbox.BezierCompletion (Number) - An indicator between 0 and 1 showing where the Hitbox is along the curve.
	    Hitbox.StartPoint (Vector3) - Starting point of the curve.
	    Hitbox.ControlPoint1 (Vector3) - Control point.
	    Hitbox.ControlPoint2 (Vector3?) - Control point. Used only in Cubic BezierMode.
	    Hitbox.EndPoint (Vector3) - End point of the curve.
	--]]
	
	
	
	HitboxSerial.Value += 1
	
	local self = setmetatable(
		{
			Serial = HitboxSerial.Value,
			Active = false,
			Constructed = false,
			Position = Vector3.new(0, 0, 0),
			Shape = "Sphere",
			Radius = 3,
			Size = Vector3.new(3, 3, 3),
			Pierce = 1,
			Debounce = 5,
			Time = 1,
			Signal = RunService.Stepped,
			Hit = ScriptSignal.new(),
		},
		Hitbox
	)
	
	local frame = 0
	local warned = false
	self.Connection = self.Signal:Connect(function(_, deltaTime)
		
		frame += 1
		
		if self:IsActive() == true then
			
			self.Time -= deltaTime

			local factor = math.floor(deltaTime / (1/60))
			if factor >= 2 then
				local velocityPerFrame = self.Velocity / (1/60)
				local steppedPos = self.Position + (self.Unit * (self.Velocity * deltaTime))
				local magnitude = (steppedPos - self.Position).magnitude
				local increaseFactor = magnitude / velocityPerFrame
				for i = 1, factor - 1 do
					if self.Mode == "Linear" then
						local middlePos = CFrame.new(self.Position):Lerp(CFrame.new(steppedPos), 1 / increaseFactor)
						
					elseif self.Mode == "Bezier" then

					end
				end
			end
			
			if self.Mode == "Linear" then
				
				self.Position += (self.Unit * (self.Velocity * deltaTime))
				
			elseif self.Mode == "Bezier" then
				
				local interpolationGain = (self.Velocity * deltaTime) / self.BezierLength
				if interpolationGain > (1 - self.BezierCompletion) then
					interpolationGain = (1 - self.BezierCompletion)
				end
				self.BezierCompletion += interpolationGain
				
				if self.BezierMode == "Quadratic" then
					self.Position = math.quadbez(self.StartPoint, self.ControlPoint1, self.EndPoint, self.BezierCompletion)
					
				elseif self.BezierMode == "Cubic" then
					self.Position = math.cubicbez(self.StartPoint, self.ControlPoint1, self.ControlPoint2, self.EndPoint, self.BezierCompletion)
					
				end
				
			elseif self:IsAttachment() == true and self.Attachment ~= nil then
				
				self.Position = self.Attachment.WorldCFrame.Position
				
			end
			
			if frame >= 5 and self.Visual ~= nil then
				
				frame = 0
				
				if self.Shape == "Sphere" then
					self.Visual.Shape = Enum.PartType.Ball
					self.Visual.Size = Vector3.new(self.Radius * 2, self.Radius * 2, self.Radius * 2)
				else
					self.Visual.Shape = Enum.PartType.Block
					self.Visual.Size = self.Size
				end
				
				if self.Position ~= nil then
					self.Visual.Position = self.Position
				end
				
			end
			
			if self.Pierce > 0 then
				
				local result: {BasePart} = CheckAtPos(self)
				if result == false and frame == 5 and warned == false then
					warned = true
					warn("[Hitbox]: Hitbox serial " ..self.Serial.. " has an invalid shape.")
				end

				if #result > 0 then
					local hitHumanoids = {}
					local registeredHumanoids: {Humanoid} = {}

					for _,v in ipairs(result) do
						local hum = v.Parent:FindFirstChildOfClass("Humanoid")
						if hum then
							if v.Parent:FindFirstChildOfClass("ForceField") == nil and v.Parent:FindFirstChild("HitboxSerial" .. self:GetSerial()) == nil then
								table.insert(hitHumanoids, {hum, v})
							end
						end
					end
					
					for _,v in pairs(hitHumanoids) do
						
						local canHit: boolean = true
						for _,v2 in ipairs(registeredHumanoids) do
							if v[1] == v2 then
								canHit = false
								break
							end
						end
						
						if canHit == true then
							
							if self:GetDebounce() > 0 then
								local newSerial: BoolValue = Instance.new("BoolValue")
								Debris:AddItem(newSerial, self:GetDebounce())
								newSerial.Name = "HitboxSerial" .. self:GetSerial()
								newSerial.Value = true
								newSerial.Parent = v.Parent
							end
							
							self.Hit:Fire(v[1], v[2], {
								["Serial"] = self.Serial,
								["Mode"] = self.Mode,
								["Attachment"] = self.Attachment or false,
								["Position"] = self.Position,
								["Radius"] = self.Radius or 0,
								["Size"] = self.Size or Vector3.new(0, 0, 0),
								["Pierce"] = self.Pierce - 1
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
			
			if self.Time <= 0 and self.Mode ~= "Bezier" then
				self:Destroy()
			end
			
			if self.Mode == "Bezier" then
				if self.BezierCompletion >= 1 then
					self:Destroy()
				end
			end

		end
	end)
	
	function self:Visualize()
		
		if self.Visual ~= nil then
			warn("[Hitbox]: Hitbox is already visualizing.")
			return nil
		end
		
		self.Visual = Instance.new("Part")
		self.Visual.Name = "HitboxVisualization" .. tostring(self:GetSerial())
		self.Visual.Anchored = true
		self.Visual.CanCollide = false
		self.Visual.BrickColor = BrickColor.new("Really red")
		self.Visual.Transparency = 0.75
		self.Visual.Material = Enum.Material.SmoothPlastic
		self.Visual.Position = self.Position or Vector3.new(0, 0, 0)
		
		if self.Shape == "Sphere" then
		    self.Visual.Shape = Enum.PartType.Ball
			self.Visual.Size = Vector3.new(self.Radius * 2, self.Radius * 2, self.Radius * 2)
		else
			self.Visual.Shape = Enum.PartType.Block
			self.Visual.Size = self.Size
		end
		
		self.Visual.Parent = workspace
		
		return self.Visual
		
	end
	
	function self:Unvisualize()
		
		if self.Visual == nil then
			warn("[Hitbox]: Hitbox is not visualizing.")
			return false
		end
		
		self.Visual:Destroy()
		self.Visual = nil
		
		return true
		
	end
	
	function self:Activate()
		self.Active = true
	end
	
	function self:Deactivate()
		self.Active = false
	end
	
	function self:IsActive()
		return self.Active or false
	end
	
	function self:IsConstructed()
		return self.Constructed or false
	end
	
	function self:IsAttachment()
		return self.UseAttachment or false
	end
	
	function self:GetSerial()
		return self.Serial
	end
	
	function self:GetCurrentSerial()
		return HitboxSerial.Value
	end
	
	function self:GetDebounce()
		return self.Debounce
	end
	
	function self:GetMode()
		return self.Mode or nil
	end
	
	function self:AddIgnore(object: Instance)
		
		if typeof(object) == "Instance" then
			if object:IsA("BasePart") or object:IsA("Model") then
				local oldList = self.OverlapParams.FilterDescendantsInstances or {}
				table.insert(oldList, object)
				self.OverlapParams.FilterDescendantsInstances = oldList
				return true
			end
		end
		
		return false
		
	end
	
	function self:RemoveIgnore(object: Instance)
		
		if typeof(object) == "Instance" then
			if object:IsA("BasePart") or object:IsA("Model") then
				
				local indexes: {number} = {}
				local oldList = self.OverlapParams.FilterDescendantsInstances
				for i,v in ipairs(oldList) do
					if v == object then
						table.insert(indexes, i)
					end
				end
				
				for i,v in ipairs(indexes) do
					table.remove(oldList, v)
					for i2,v2 in ipairs(indexes) do
						if i2 > i and v2 > v then
							indexes[i2] -= 1
						end
					end
				end
				self.OverlapParams.FilterDescendantsInstances = oldList
				
				return #indexes
				
			end
		end
		
		return 0
		
	end
	
	function self:ChangeOverlapParams(args)
		
		self.OverlapParams.FilterDescendantsInstances = args["IgnoreList"] or self.OverlapParams.FilterDescendantsInstances
		self.OverlapParams.RespectCanCollide = args["RespectCanCollide"] or self.OverlapParams.RespectCanCollide
		self.OverlapParams.MaxParts = args["MaxParts"] or self.OverlapParams.MaxParts
		
		if args["CollisionGroup"] ~= nil then
			self.OverlapParams.CollisionGroup = args["CollisionGroup"]
		end
		
		return true
		
	end
	
	function self:ChangeAttachment(attachment: Attachment)
		
		self.UseAttachment = pcall(function()
			return attachment:IsA("Attachment")
		end) or false
		self.Attachment = attachment
		
		return self:IsAttachment()
		
	end
	
	function self:Disconnect()
		
		if self.Connection ~= nil then

			if typeof(self.Connection) == "RBXScriptConnection" then
				self.Connection:Disconnect() 
			end

		end

		return true
		
	end
	
	function self:DisconnectAll()
		self.Hit:DisconnectAll()
		return true
	end
	
	function self:ConstructLinear(args)
        
		if self:IsConstructed() == true then
			warn("[Hitbox]: Cannot ConstructLinear because Hitbox trajectory is already constructed.")
			return false
		end

		if args["Velocity"] == nil then
			warn("[Hitbox]: ConstructLinear missing argument(s).")
			return false
		end

		xpcall(function()
			self.Unit = args["Unit"] or (args["Position"] - self.Position).Unit
		end, function()
			error("[Hitbox]: ConstructLinear missing argument(s).")
		end)

		self.Velocity = args["Velocity"]

		self.Mode = "Linear"
		self.Constructed = true

		return true

	end
	
	function self:ConstructBezier(args)

		if self:IsConstructed() == true then
			warn("[Hitbox]: Cannot ConstructBezier because Hitbox trajectory is already constructed.")
			return false
		end

		if args["Start"] == nil or args["End"] == nil or args["Control1"] == nil then
			warn("[Hitbox]: ConstructBezier missing argument(s).")
			return false
		end
		
		self.StartPoint = args["Start"]
		self.EndPoint = args["End"]
		self.ControlPoint1 = args["Control1"]
		self.Velocity = args["Velocity"]
		self.BezierCompletion = 0
		
		if args["Mode"] == "Quadratic" then
			
			self.BezierMode = "Quadratic"
			self.BezierLength = math.quadbezlen(self.StartPoint, self.ControlPoint1, self.EndPoint)
			
		elseif args["Mode"] == "Cubic" then
			
			if args["Control2"] == nil then
				warn("[Hitbox]: ConstructBezier missing argument(s).")
				return false
			end			
			
			self.BezierMode = "Cubic"
			self.ControlPoint2 = args["Control2"]
			self.BezierLength = math.cubicbezlen(self.StartPoint, self.ControlPoint1, self.ControlPoint2, self.EndPoint)
			
		end
		
		self.Position = self.StartPoint
		
		self.Mode = "Bezier"
		self.Constructed = true
		
		return true

	end
	
	function self:Deconstruct(bypass: boolean?)

		if self:IsActive() == true and (bypass == false or bypass == nil) then
			warn("[Hitbox]: Cannot deconstruct because Hitbox is active.")
			return false
		end
        
		if self:IsConstructed() == false and (bypass == false or bypass == nil) then
			warn("[Hitbox]: Cannot deconstruct because Hitbox has no constructed trajectory.")
			return false
		end
		
		self.Hit:DisconnectAll()
		
		if self.Visual ~= nil then
			pcall(self.Visual.Destroy, self.Visual)
		end
		self.Visual = nil

		self.Unit = nil
		self.OverlapParams = nil
		self.Velocity = nil
		
		self.StartPoint = nil
		self.EndPoint = nil
		self.ControlPoint1 = nil
		self.ControlPoint2 = nil
		self.BezierMode = nil
		self.BezierCompletion = nil
		self.BezierLength = nil

		self.Mode = nil
		self.Constructed = false

		return true

	end
	
	function self:Destroy()
		self.Active = false
		
		self:Deconstruct(true)
		
		self.Hit = nil
		self = {}
		return true
	end
	
	self.OverlapParams = OverlapParams.new()
	self.OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
	self.OverlapParams.FilterDescendantsInstances = {}
	self.OverlapParams.RespectCanCollide = false
	self.OverlapParams.MaxParts = 0
	
	self:ChangeAttachment(attachment)
	
	if self:IsAttachment() == true then
		self.Position = self.Attachment.WorldCFrame.Position
	end
	
	return self
	
end

function Hitbox:IsHitboxBackstab(Part: BasePart, HitboxDataBundle)
	
	if HitboxDataBundle.Radius > 100 or HitboxDataBundle.Size.X > 50 or HitboxDataBundle.Size.Y > 50 or HitboxDataBundle.Size.Z > 50 then
		warn("[Hitbox]: Hitbox is too large to support backstab detection. (Maximum 50 axis-radius)")
		return false
	elseif CFrame.new(HitboxDataBundle.Position):inverse() * Part.CFrame < 0 then
		return true
	end
	
	return false
	
end

function Hitbox:IsBackstab(Part: BasePart, Character: Model)
	
	local root: BasePart? = Character:FindFirstChild("HumanoidRootPart")
    if root then
		if root.CFrame:inverse() * Part.CFrame < 0 then
			return true
		end
	end
	
	warn("[Hitbox]: Provided Character has no HumanoidRootPart.")
	return false
	
end

return Hitbox