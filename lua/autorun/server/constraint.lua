local MaxConstraints = 100


--[[----------------------------------------------------------------------
	CreateConstraintSystem
------------------------------------------------------------------------]]
local function CreateConstraintSystem()

	local System = ents.Create("phys_constraintsystem")
		System:SetKeyValue( "additionaliterations", GetConVarNumber( "gmod_physiterations" ) )
		System:Spawn()
		System:Activate()

	System.Constraints = 0

	return System

end


--[[----------------------------------------------------------------------
	FindOrCreateConstraintSystem
	
	Associates entities with a constraint system. If both entities already
	have a constraint system then the one that is closest to being full is
	chosen. Otherwise, if one entity has a constraint system then the other
	is associated with it.
	If there are no existing constraint systems then a new one is created.
------------------------------------------------------------------------]]
local function FindOrCreateConstraintSystem( Ent1, Ent2 )

	local System

	if IsValid(Ent1.ConstraintSystem) and IsValid(Ent2.ConstraintSystem) then

		local Sys1 = Ent1.ConstraintSystem
		local Sys2 = Ent2.ConstraintSystem

		if Sys1.Constraints < MaxConstraints and Sys1.Constraints >= Sys2.Constraints then
			System = Sys1
		elseif Sys2.Constraints < MaxConstraints and Sys2.Constraints >= Sys1.Constraints then
			System = Sys2
		else
			System = CreateConstraintSystem()
		end

	elseif IsValid(Ent1.ConstraintSystem) then

		if Ent1.ConstraintSystem.Constraints < MaxConstraints then
			System = Ent1.ConstraintSystem
		else
			System = CreateConstraintSystem()
		end

	elseif IsValid(Ent2.ConstraintSystem) then

		if Ent2.ConstraintSystem.Constraints < MaxConstraints then
			System = Ent2.ConstraintSystem
		else
			System = CreateConstraintSystem()
		end

	else
		System = CreateConstraintSystem()
	end


	if not Ent1.ConstraintSystem then Ent1.ConstraintSystem = System end
	if not Ent2.ConstraintSystem then Ent2.ConstraintSystem = System end

	System.Constraints = System.Constraints+1

	return System

end


--[[----------------------------------------------------------------------
	local System = onStartConstraint( Ent1, Ent2 )
	Should be called before creating a constraint
------------------------------------------------------------------------]]
local function onStartConstraint( Ent1, Ent2 )

	-- Get constraint system
	local System = FindOrCreateConstraintSystem( Ent1, Ent2 )

	-- Any constraints called after this call will use this system
	SetPhysConstraintSystem( System )

	return System
end

--[[----------------------------------------------------------------------
	onFinishConstraint( Ent1, Ent2 )
	Should be called before creating a constraint
------------------------------------------------------------------------]]
local function onFinishConstraint( Ent1, Ent2 )

	-- Turn off constraint system override
	SetPhysConstraintSystem( NULL )

end

local function onRemoveConstraint(Constraint)

	local System = Constraint.ConstraintSystem
	System.Constraints = System.Constraints-1

	if System.Constraints == 0 then System:Remove() end

end

local function SetPhysicsCollisions( Ent, b )

	if not IsValid( Ent ) or not IsValid( Ent:GetPhysicsObject() ) then return end

	Ent:GetPhysicsObject():EnableCollisions( b )

end

--[[----------------------------------------------------------------------
	RemoveConstraints( Ent, Type )
	Removes all constraints of type from entity
------------------------------------------------------------------------]]
local function RemoveConstraints( Ent, Type )

	if not Ent.Constraints then return end

	local c = Ent.Constraints
	local i = 0

	for k, v in pairs( c ) do

		if not IsValid( v ) then

			c[ k ] = nil

		elseif v.Type == Type then

			-- Make sure physics collisions are on!
			-- If we don't the unconstrained objects will fall through the world forever.
			SetPhysicsCollisions( v.Ent1, true )
			SetPhysicsCollisions( v.Ent2, true )

			c[ k ] = nil
			v:Remove()

			i = i + 1
		end

	end

	if table.Count( c ) == 0 then
		-- Update the network var and clear the constraints table.
		Ent:IsConstrained()
	end

	local bool = i ~= 0
	return bool, i

end


--[[----------------------------------------------------------------------
	RemoveAll( Ent )
	Removes all constraints from entity
------------------------------------------------------------------------]]
function RemoveAll( Ent )

	if not Ent.Constraints then return end

	local c = Ent.Constraints
	local i = 0
	for k, v in pairs( c ) do

		if IsValid(v) then

			-- Make sure physics collisions are on!
			-- If we don't the unconstrained objects will fall through the world forever.
			SetPhysicsCollisions( v.Ent1, true )
			SetPhysicsCollisions( v.Ent2, true )

			v:Remove()
			i = i + 1
		end
	end

	-- Update the network var and clear the constraints table.
	Ent:IsConstrained()

	local bool = i ~= 0
	return bool, i

end

--[[----------------------------------------------------------------------
	Find( Ent1, Ent2, Type, Bone1, Bone2 )
	Removes all constraints from entity
------------------------------------------------------------------------]]
local function Find( Ent1, Ent2, Type, Bone1, Bone2 )

	if not Ent1.Constraints then return end

	local c = Ent1.Constraints

	for k, v in pairs( Ent1.Constraints ) do

		if IsValid(v) then

			local CTab = v

			if CTab.Type == Type and CTab.Ent1 == Ent1 and CTab.Ent2 == Ent2 and CTab.Bone1 == Bone1 and CTab.Bone2 == Bone2 then
				return v
			end

			if CTab.Type == Type and CTab.Ent2 == Ent1 and CTab.Ent1 == Ent2 and CTab.Bone2 == Bone1 and CTab.Bone1 == Bone2 then
				return v
			end

		end

	end

	return nil

end

--[[----------------------------------------------------------------------
	CanConstrain( Ent, Bone )
	Returns false if we shouldn't be constraining this entity
------------------------------------------------------------------------]]
local function CanConstrain( Ent, Bone )

	if not Ent then return false end
	if not isnumber( Bone ) then return false end
	if not Ent:IsWorld() and not IsValid(Ent) then return false end
	if not Ent:GetPhysicsObjectNum( Bone ) or not IsValid(Ent:GetPhysicsObjectNum( Bone )) then return false end

	return true

end

--[[----------------------------------------------------------------------
	CalcElasticConsts( ... )
	This attempts to scale the elastic constraints such as the winch
	to keep a stable but responsive constraint..
------------------------------------------------------------------------]]
local function CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, iFixed )

	local minMass = 0

	if Ent1:IsWorld() then minMass = Phys2:GetMass()
	elseif Ent2:IsWorld() then minMass = Phys1:GetMass()
	else
		minMass = math.min( Phys1:GetMass(), Phys2:GetMass() )
	end

	-- const, damp
	local const = minMass * 100
	local damp = const * 0.2

	if iFixed == 0 then

		const = minMass * 50
		damp = const * 0.1

	end

	return const, damp

end


--[[----------------------------------------------------------------------
	CreateKeyframeRope( ... )
	Creates a rope without any constraint
------------------------------------------------------------------------]]
local function CreateKeyframeRope( Pos, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, kv )

	-- No rope if 0 or minus
	if width <= 0 then return nil end

	-- Clamp the rope to a sensible width
	width = math.Clamp( width, 1, 100 )

	local rope = ents.Create( "keyframe_rope" )
	rope:SetPos( Pos )
	rope:SetKeyValue( "Width", width )

	if isstring( material ) then
		local mat = Material( material )
		if material and not string.find( mat:GetShader():lower(), "spritecard" ) then rope:SetKeyValue( "RopeMaterial", material ) end
	end

	-- Attachment point 1
	rope:SetEntity( "StartEntity", Ent1 )
	rope:SetKeyValue( "StartOffset", tostring( LPos1 ) )
	rope:SetKeyValue( "StartBone", Bone1 )

	-- Attachment point 2
	rope:SetEntity( "EndEntity", Ent2 )
	rope:SetKeyValue( "EndOffset", tostring( LPos2 ) )
	rope:SetKeyValue( "EndBone", Bone2 )

	if kv then
		for k, v in pairs( kv ) do

			rope:SetKeyValue( k, tostring( v ) )

		end
	end

	rope:Spawn()
	rope:Activate()

	-- Delete the rope if the attachments get killed
	Ent1:DeleteOnRemove( rope )
	Ent2:DeleteOnRemove( rope )
	if Constraint and IsValid(Constraint) then Constraint:DeleteOnRemove( rope ) end

	return rope

end

--[[----------------------------------------------------------------------
	AddConstraintTable( Ent, Constraint, Ent2 )
	Stores info about the constraints on the entity's table
------------------------------------------------------------------------]]
local function AddConstraintTable( Ent, Constraint, Ent2 )

	if not IsValid( Constraint ) then return end

	if IsValid(Ent) then

		Ent.Constraints = Ent.Constraints or {}
		table.insert( Ent.Constraints, Constraint )
		
		Ent:DeleteOnRemove( Constraint )

	end

	if Ent2 and Ent2 ~= Ent then
		Ent2.Constraints = Ent2.Constraints or {}
		table.insert( Ent2.Constraints, Constraint )
		
		Ent2:DeleteOnRemove( Constraint )
	end

end

--[[----------------------------------------------------------------------
	AddConstraintTableNoDelete( Ent, Constraint, Ent2 )
	Stores info about the constraints on the entity's table
------------------------------------------------------------------------]]
local function AddConstraintTableNoDelete( Ent, Constraint, Ent2 )

	if not IsValid( Constraint ) then return end

	if IsValid(Ent) then

		Ent.Constraints = Ent.Constraints or {}

		table.insert( Ent.Constraints, Constraint )

	end

	if Ent2 and Ent2 ~= Ent then
		Ent2.Constraints = Ent2.Constraints or {}
		
		table.insert( Ent2.Constraints, Constraint )
	end

end


--[[----------------------------------------------------------------------
	Weld( ... )
	Creates a solid weld constraint
------------------------------------------------------------------------]]
local function Weld( Ent1, Ent2, Bone1, Bone2, forcelimit, nocollide, deleteonbreak )

	if Ent1 == Ent2 and Bone1 == Bone2 then return false end
	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	if Find( Ent1, Ent2, "Weld", Bone1, Bone2 ) then

		-- A weld already exists between these two physics objects.
		-- There's totally no point in re-creating it. It doesn't make
		-- the weld any stronger - that's just an urban legend.
		return false

	end

	-- Don't weld World to objects, weld objects to World!
	-- Prevents crazy physics on some props
	if Ent1:IsWorld() then
		Ent1 = Ent2
		Ent2 = game.GetWorld()
	end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )

	local System = onStartConstraint( Ent1, Ent2 )

	-- Create the constraint
	local Constraint = ents.Create( "phys_constraint" )
	
	if forcelimit then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
	if nocollide then Constraint:SetKeyValue( "spawnflags", 1 ) end
	
	Constraint:SetPhysConstraintObjects( Phys2, Phys1 )
	Constraint:Spawn()
	Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )
	AddConstraintTable( Ent1, Constraint, Ent2 )

	-- Optionally delete Ent1 when the weld is broken
	-- This is to fix bug #310
	if deleteonbreak then
		Ent2:DeleteOnRemove( Ent1 )
	end

	-- Make a constraints table
	local ctable = {
		Type = "Weld",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		forcelimit = forcelimit,
		nocollide = nocollide,
		deleteonbreak = deleteonbreak,
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	Phys1:Wake()
	Phys2:Wake()

	return Constraint

end
duplicator.RegisterConstraint( "Weld", Weld, "Ent1", "Ent2", "Bone1", "Bone2", "forcelimit", "nocollide", "deleteonbreak" )


--[[----------------------------------------------------------------------
	Rope( ... )
	Creates a rope constraint - with rope!
------------------------------------------------------------------------]]
local function Rope( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, length, addlength, forcelimit, width, material, rigid )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )
	local addlength = math.Clamp( addlength or 0, -56756, 56756 )
	local Constraint = nil
	local System = nil

	-- Make Constraint
	if Phys1 ~= Phys2 then

		local System = onStartConstraint( Ent1, Ent2 )

			-- Create the constraint
			Constraint = ents.Create( "phys_lengthconstraint" )
			Constraint:SetPos( WPos1 )
			Constraint:SetKeyValue( "attachpoint", tostring( WPos2 ) )
			Constraint:SetKeyValue( "minlength", "0.0" )
			Constraint:SetKeyValue( "length", length + addlength )
			if forcelimit then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
			if rigid then Constraint:SetKeyValue( "spawnflags", 2 ) end
			Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
			Constraint:Spawn()
			Constraint:Activate()

		onFinishConstraint( Ent1, Ent2 )

	end

	-- Make Rope
	local kv = {
		Length = length + addlength,
		Collide = 1
	}
	if rigid then kv.Type = 2 end

	local rope = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, kv )

	-- What the fuck
	if not Constraint then Constraint, rope = rope, nil end

	local ctable = {
		Type = "Rope",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		length = length,
		addlength = addlength,
		forcelimit = forcelimit,
		width = width,
		material = material,
		rigid = rigid,
		ConstraintSystem = System
	}

	if IsValid( Constraint ) then
		Constraint:SetTable( ctable )
		Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

		AddConstraintTable( Ent1, Constraint, Ent2 )
	end

	return Constraint, rope

end
duplicator.RegisterConstraint( "Rope", Rope, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "length", "addlength", "forcelimit", "width", "material", "rigid" )

--[[----------------------------------------------------------------------
	Elastic( ... )
	Creates an elastic constraint
------------------------------------------------------------------------]]
local function Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, constant, damping, rdamping, material, width, stretchonly )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	local Constraint = nil
	local rope = nil

	-- Make Constraint
	if Phys1 ~= Phys2 then

		local System = onStartConstraint( Ent1, Ent2 )

			Constraint = ents.Create( "phys_spring" )
			Constraint:SetPos( WPos1 )
			Constraint:SetKeyValue( "springaxis", tostring( WPos2 ) )
			Constraint:SetKeyValue( "constant", constant )
			Constraint:SetKeyValue( "damping", damping )
			Constraint:SetKeyValue( "relativedamping", rdamping )
			Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
			if stretchonly == 1 or stretchonly == true then
				Constraint:SetKeyValue( "spawnflags", 1 )
			end

			Constraint:Spawn()
			Constraint:Activate()

		onFinishConstraint( Ent1, Ent2 )
		AddConstraintTable( Ent1, Constraint, Ent2 )

		local ctable = {
			Type = "Elastic",
			Ent1 = Ent1,
			Ent2 = Ent2,
			Bone1 = Bone1,
			Bone2 = Bone2,
			LPos1 = LPos1,
			LPos2 = LPos2,
			constant = constant,
			damping = damping,
			rdamping = rdamping,
			material = material,
			width = width,
			length = ( WPos1 - WPos2 ):Length(),
			stretchonly = stretchonly,
			ConstraintSystem = System
		}

		Constraint:SetTable( ctable )
		Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

		-- Make Rope
		local kv = {
			Collide = 1,
			Type = 0
		}

		rope = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, kv )
	end

	return Constraint, rope
end
duplicator.RegisterConstraint("Elastic", Elastic, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "constant", "damping", "rdamping", "material", "width", "stretchonly")


--[[----------------------------------------------------------------------
	Keepupright( ... )
	Creates a KeepUpright constraint
------------------------------------------------------------------------]]
local function Keepupright( Ent, Ang, Bone, angularlimit )

	if not CanConstrain( Ent, Bone ) then return false end
	if Ent:GetClass() ~= "prop_physics" and Ent:GetClass() ~= "prop_ragdoll" then return false end
	if not angularlimit or angularlimit < 0 then return end

	local Phys = Ent:GetPhysicsObjectNum(Bone)

	-- Remove any KU's already on entity
	RemoveConstraints( Ent, "Keepupright" )

	onStartConstraint( Ent )

		local Constraint = ents.Create( "phys_keepupright" )
		Constraint:SetAngles( Ang )
		Constraint:SetKeyValue( "angularlimit", angularlimit )
		Constraint:SetPhysConstraintObjects( Phys, Phys )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent )
	AddConstraintTable( Ent, Constraint )

	local ctable = {
		Type = "Keepupright",
		Ent1 = Ent,
		Ang = Ang,
		Bone = Bone,
		angularlimit = angularlimit,
		ConstraintSystem = System
	}
	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	--
	-- This is a hack to keep the KeepUpright context menu in sync..
	--
	Ent:SetNWBool( "IsUpright", true )

	return Constraint

end
duplicator.RegisterConstraint( "Keepupright", Keepupright, "Ent1", "Ang", "Bone", "angularlimit" )


local function CreateStaticAnchorPoint( Pos )

	-- Creates an invisible frozen, not interactive prop.
	local Anchor = ents.Create( "gmod_anchor" )

	Anchor:SetPos( Pos )
	Anchor:Spawn()
	Anchor:Activate()

	return Anchor, Anchor:GetPhysicsObject(), 0, Vector( 0, 0, 0 )

end


--[[----------------------------------------------------------------------
	Slider( ... )
	Creates a slider constraint
------------------------------------------------------------------------]]
local function Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, width, material )

	-- TODO: If we get rid of sliders we can get rid of gmod_anchor too!

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )
	local StaticAnchor = nil

	-- Make Constraint
	if Phys1 == Phys2 then return end

	-- Make Rope
	local kv = {
		Collide = 0,
		Type = 2,
		Subdiv = 1,
	}

	-- Start World Hack.
	-- Attaching a slider to the world makes it really sucks so we make
	-- a prop and attach to that.

	if Ent1:IsWorld() then

		Ent1, Phys1, Bone1, LPos1 = CreateStaticAnchorPoint( WPos1 )
		StaticAnchor = Ent1

	end

	if Ent2:IsWorld() then

		Ent2, Phys2, Bone2, LPos2 = CreateStaticAnchorPoint( WPos2 )
		StaticAnchor = Ent2

	end

	-- End World Hack.

	local System = onStartConstraint( Ent1, Ent2 )

		local Constraint = ents.Create("phys_slideconstraint")
		Constraint:SetPos( WPos1 )
		Constraint:SetKeyValue( "slideaxis", tostring( WPos2 ) )
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )
	AddConstraintTable( Ent1, Constraint, Ent2 )

	local rope = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, kv )

	-- If we have a static anchor - delete it when we die.
	if StaticAnchor then

		Constraint:DeleteOnRemove( StaticAnchor )

	end

	local ctable = {
		Type = "Slider",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		width = width,
		material = material,
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	return Constraint, rope

end
duplicator.RegisterConstraint( "Slider", Slider, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "width", "material" )

--[[----------------------------------------------------------------------
	Axis( ... )
	Creates an axis constraint
------------------------------------------------------------------------]]
local function Axis( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, forcelimit, torquelimit, friction, nocollide, LocalAxis, DontAddTable )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	-- If we have a LocalAxis, use that
	if LocalAxis then
		WPos2 = Phys1:LocalToWorld( LocalAxis )
	end

	local System = onStartConstraint( Ent1, Ent2 )

		local Constraint = ents.Create("phys_hinge")
		Constraint:SetPos( WPos1 )
		Constraint:SetKeyValue( "hingeaxis", tostring( WPos2 ) )
		if forcelimit and forcelimit > 0 then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
		if torquelimit and torquelimit > 0 then Constraint:SetKeyValue( "torquelimit", torquelimit ) end
		if friction and friction > 0 then Constraint:SetKeyValue( "hingefriction", friction ) end
		if nocollide and nocollide > 0 then Constraint:SetKeyValue( "spawnflags", 1 ) end
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )

	if not DontAddTable then
		AddConstraintTable( Ent1, Constraint, Ent2 )
	end

	local ctable = {
		Type = "Axis",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		forcelimit = forcelimit,
		torquelimit = torquelimit,
		friction = friction,
		nocollide = nocollide,
		LocalAxis = Phys1:WorldToLocal( WPos2 ),
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	return Constraint

end
duplicator.RegisterConstraint( "Axis", Axis, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "forcelimit", "torquelimit", "friction", "nocollide", "LocalAxis", "DontAddTable" )


--[[----------------------------------------------------------------------
	AdvBallsocket( ... )
	Creates an advanced ballsocket (ragdoll) constraint
------------------------------------------------------------------------]]
function AdvBallsocket( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, forcelimit, torquelimit, xmin, ymin, zmin, xmax, ymax, zmax, xfric, yfric, zfric, onlyrotation, nocollide )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	-- Make Constraint
	local System = onStartConstraint( Ent1, Ent2 )

		local flags = 0
		if onlyrotation and onlyrotation > 0 then flags = flags + 2 end
		if nocollide and nocollide > 0 then flags = flags + 1 end

		local Constraint = ents.Create("phys_ragdollconstraint")
		Constraint:SetPos( WPos1 )
		Constraint:SetKeyValue( "xmin", xmin )
		Constraint:SetKeyValue( "xmax", xmax )
		Constraint:SetKeyValue( "ymin", ymin )
		Constraint:SetKeyValue( "ymax", ymax )
		Constraint:SetKeyValue( "zmin", zmin )
		Constraint:SetKeyValue( "zmax", zmax )
		if xfric and xfric > 0 then Constraint:SetKeyValue( "xfriction", xfric ) end
		if yfric and yfric > 0 then Constraint:SetKeyValue( "yfriction", yfric ) end
		if zfric and zfric > 0 then Constraint:SetKeyValue( "zfriction", zfric ) end
		if forcelimit and forcelimit > 0 then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
		if torquelimit and torquelimit > 0 then Constraint:SetKeyValue( "torquelimit", torquelimit ) end
		Constraint:SetKeyValue( "spawnflags", flags )
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )
	AddConstraintTable( Ent1, Constraint, Ent2 )

	local ctable = {
		Type = "AdvBallsocket",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		forcelimit = forcelimit,
		torquelimit = torquelimit,
		xmin = xmin,
		ymin = ymin,
		zmin = zmin,
		xmax = xmax,
		ymax = ymax,
		zmax = zmax,
		xfric = xfric,
		yfric = yfric,
		zfric = zfric,
		onlyrotation = onlyrotation,
		nocollide = nocollide,
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	return Constraint

end
duplicator.RegisterConstraint( "AdvBallsocket", AdvBallsocket, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "forcelimit", "torquelimit", "xmin", "ymin", "zmin", "xmax", "ymax", "zmax", "xfric", "yfric", "zfric", "onlyrotation", "nocollide")


--[[----------------------------------------------------------------------
	NoCollide( ... )
	Creates an nocollide `constraint'
------------------------------------------------------------------------]]
local function NoCollide( Ent1, Ent2, Bone1, Bone2 )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )

	if Phys1 == Phys2 then return false end

	if Find( Ent1, Ent2, "NoCollide", Bone1, Bone2 ) then

		return false

	end

	-- Make Constraint
	local Constraint = ents.Create("logic_collision_pair")
		Constraint:SetKeyValue( "startdisabled", 1 )
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()
		Constraint:Input( "DisableCollisions", nil, nil, nil )

	AddConstraintTable( Ent1, Constraint, Ent2 )

	local ctable = {
		Type = "NoCollide",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2
	}

	Constraint:SetTable( ctable )

	return Constraint

end
duplicator.RegisterConstraint( "NoCollide", NoCollide, "Ent1", "Ent2", "Bone1", "Bone2" )


--[[----------------------------------------------------------------------
	MotorControl( pl, motor, onoff, dir )
	Numpad controls for the motor constraints
------------------------------------------------------------------------]]
local function MotorControl( pl, motor, onoff, dir )

	if not IsValid(motor) then return false end

	local activate = false

	if motor.toggle == 1 then

		-- Toggle mode, only do something when the key is pressed
		-- if the motor is off, turn it on, and vice-versa.
		-- This only happens if the same key as the current
		-- direction is pressed, otherwise the direction is changed
		-- with the motor being left on.

		if onoff then

			if motor.direction == dir or not motor.is_on then

				-- Direction is the same, Activate if the motor is off
				-- Deactivate if the motor is on.

				motor.is_on = not motor.is_on

				activate = motor.is_on

			else

				-- Change of direction, make sure it's activated

				activate = true

			end

		else

			return

		end

	else

		-- normal mode: activate is based on the key status
		-- (down = on, up = off)

		activate = onoff

	end

	if activate then

		motor:Fire( "Activate", "", 0 ) -- Turn on the motor
		motor:Fire( "Scale", dir, 0 ) -- This makes the direction change

	else
		motor:Fire( "Deactivate", "", 0 ) -- Turn off the motor
	end

	motor.direction = dir

	return true

end
numpad.Register( "MotorControl", MotorControl )

--[[----------------------------------------------------------------------
	Motor( ... )
	Creates a motor constraint
------------------------------------------------------------------------]]
local function Motor( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, friction, torque, forcetime, nocollide, toggle, pl, forcelimit, numpadkey_fwd, numpadkey_bwd, direction, LocalAxis )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	-- Get information we're about to use
	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	if LocalAxis then
		WPos2 = Phys1:LocalToWorld( LocalAxis )
	end

	-- The true at the end stops it adding the axis table to the entity's count stuff.
	local axis = Axis( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0, 0, friction, nocollide, LocalAxis, true )

	-- Delete the axis when either object dies
	Ent1:DeleteOnRemove( axis )
	Ent2:DeleteOnRemove( axis )

	-- Create the constraint
	local System = onStartConstraint( Ent1, Ent2 )

		local Constraint = ents.Create( "phys_torque" )
		Constraint:SetPos( WPos1 )
		Constraint:SetKeyValue( "axis", tostring( WPos2 ) )
		Constraint:SetKeyValue( "force", torque )
		Constraint:SetKeyValue( "forcetime", forcetime )
		Constraint:SetKeyValue( "spawnflags", 4 )
		Constraint:SetPhysConstraintObjects( Phys1, Phys1 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )

	AddConstraintTableNoDelete( Ent1, Constraint, Ent2 )

	direction = direction or 1

	LocalAxis = Phys1:WorldToLocal( WPos2 )

	-- Delete the phys_torque too!
	axis:DeleteOnRemove( Constraint )

	-- Delete the axis constrain if phys_torque is deleted, with something like Motor tools reload
	Constraint:DeleteOnRemove( axis )

	local ctable = {
		Type = "Motor",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		friction = friction,
		torque = torque,
		forcetime = forcetime,
		nocollide = nocollide,
		toggle = toggle,
		pl = pl,
		forcelimit = forcelimit,
		forcescale = 0,
		direction = direction,
		is_on = false,
		numpadkey_fwd = numpadkey_fwd,
		numpadkey_bwd = numpadkey_bwd,
		LocalAxis = LocalAxis,
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	if numpadkey_fwd then

		numpad.OnDown( pl, numpadkey_fwd, "MotorControl", Constraint, true, 1 )
		numpad.OnUp( pl, numpadkey_fwd, "MotorControl", Constraint, false, 1 )
	end

	if numpadkey_bwd then

		numpad.OnDown( pl, numpadkey_bwd, "MotorControl", Constraint, true, -1 )
		numpad.OnUp( pl, numpadkey_bwd, "MotorControl", Constraint, false, -1 )

	end

	return Constraint, axis

end
duplicator.RegisterConstraint( "Motor", Motor, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "friction", "torque", "forcetime", "nocollide", "toggle", "pl", "forcelimit", "numpadkey_fwd", "numpadkey_bwd", "direction", "LocalAxis" )


--[[----------------------------------------------------------------------
	Pulley( ... )
	Creates a pulley constraint
------------------------------------------------------------------------]]
local function Pulley( Ent1, Ent4, Bone1, Bone4, LPos1, LPos4, WPos2, WPos3, forcelimit, rigid, width, material )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent4, Bone4 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys4 = Ent4:GetPhysicsObjectNum( Bone4 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos4 = Phys4:LocalToWorld( LPos4 )

	if Phys1 == Phys2 then return false end

	-- Make Constraint
	onStartConstraint( Ent1, Ent4 )

		local Constraint = ents.Create( "phys_pulleyconstraint" )
		Constraint:SetPos( WPos2 )
		Constraint:SetKeyValue( "position2", tostring( WPos3 ) )
		Constraint:SetKeyValue( "ObjOffset1", tostring( LPos1 ) )
		Constraint:SetKeyValue( "ObjOffset2", tostring( LPos4 ) )
		Constraint:SetKeyValue( "forcelimit", forcelimit )
		Constraint:SetKeyValue( "addlength", ( WPos3 - WPos4 ):Length() )
		if rigid then Constraint:SetKeyValue( "spawnflags", 2 ) end
		Constraint:SetPhysConstraintObjects( Phys1, Phys4 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent4 )
	AddConstraintTable( Ent1, Constraint, Ent4 )

	local ctable = {
		Type = "Pulley",
		Ent1 = Ent1,
		Ent4 = Ent4,
		Bone1 = Bone1,
		Bone4 = Bone4,
		LPos1 = LPos1,
		LPos4 = LPos4,
		WPos2 = WPos2,
		WPos3 = WPos3,
		forcelimit = forcelimit,
		rigid = rigid,
		width = width,
		material = material,
		ConstraintSystem = System
	}
	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	-- make Rope
	local World = game.GetWorld()

	local kv = {
		Collide = 1,
		Type = 2,
		Subdiv = 1,
	}

	CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, World, WPos2, 0, kv )
	CreateKeyframeRope( WPos1, width, material, Constraint, World, WPos3, 0, World, WPos2, 0, kv )
	CreateKeyframeRope( WPos1, width, material, Constraint, World, WPos3, 0, Ent4, LPos4, Bone4, kv )

	return Constraint

end
duplicator.RegisterConstraint( "Pulley", Pulley, "Ent1", "Ent4", "Bone1", "Bone4", "LPos1", "LPos4", "WPos2", "WPos3", "forcelimit", "rigid", "width", "material" )


--[[----------------------------------------------------------------------
	Ballsocket( ... )
	Creates a Ballsocket constraint
------------------------------------------------------------------------]]
local function Ballsocket( Ent1, Ent2, Bone1, Bone2, LPos, forcelimit, torquelimit, nocollide )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	-- Get information we're about to use
	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos = Phys2:LocalToWorld( LPos )

	if Phys1 == Phys2 then return false end

	local System = onStartConstraint( Ent1, Ent2 )

		local Constraint = ents.Create("phys_ballsocket")
		Constraint:SetPos( WPos )
		if forcelimit and forcelimit > 0 then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
		if torquelimit and torquelimit > 0 then Constraint:SetKeyValue( "torquelimit", torquelimit ) end
		if nocollide and nocollide > 0 then Constraint:SetKeyValue( "spawnflags", 1 ) end
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()

	onFinishConstraint( Ent1, Ent2 )
	AddConstraintTable( Ent1, Constraint, Ent2 )

	local ctable = {
		Type = "Ballsocket",
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos = LPos,
		forcelimit = forcelimit,
		torquelimit = torquelimit,
		nocollide = nocollide,
		ConstraintSystem = System
	}

	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	return Constraint

end
duplicator.RegisterConstraint( "Ballsocket", Ballsocket, "Ent1", "Ent2", "Bone1", "Bone2", "LPos", "forcelimit", "torquelimit", "nocollide" )


--[[----------------------------------------------------------------------
	Winch( ... )
	Creates a Winch constraint
------------------------------------------------------------------------]]
local function Winch( pl, Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, width, fwd_bind, bwd_bind, fwd_speed, bwd_speed, material, toggle )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	local const, dampen = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, false )

	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampen, 0, material, width, true )

	if not Constraint then return nil, rope end

	local ctable = {
		Type = "Winch",
		pl = pl,
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		width = width,
		fwd_bind = fwd_bind,
		bwd_bind = bwd_bind,
		fwd_speed = fwd_speed,
		bwd_speed = bwd_speed,
		material = material,
		toggle = toggle,
		ConstraintSystem = System
	}
	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	-- Attach our Controller to the Elastic constraint
	local controller = ents.Create( "gmod_winch_controller" )
	controller:SetConstraint( Constraint )
	controller:SetRope( rope )
	controller:Spawn()

	Constraint:DeleteOnRemove( controller )
	Ent1:DeleteOnRemove( controller )
	Ent2:DeleteOnRemove( controller )

	if toggle then

		numpad.OnDown( pl, fwd_bind, "WinchToggle", controller, 1 )
		numpad.OnDown( pl, bwd_bind, "WinchToggle", controller, -1 )

	else

		numpad.OnDown( pl, fwd_bind, "WinchOn", controller, 1 )
		numpad.OnUp( pl, fwd_bind, "WinchOff", controller )
		numpad.OnDown( pl, bwd_bind, "WinchOn", controller, -1 )
		numpad.OnUp( pl, bwd_bind, "WinchOff", controller )

	end

	return Constraint, rope, controller

end
duplicator.RegisterConstraint( "Winch", Winch, "pl", "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "width", "fwd_bind", "bwd_bind", "fwd_speed", "bwd_speed", "material", "toggle" )


--[[----------------------------------------------------------------------
	Hydraulic( ... )
	Creates a Hydraulic constraint
------------------------------------------------------------------------]]
local function Hydraulic( pl, Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, Length1, Length2, width, key, fixed, speed, material )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	local const, dampn = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, fixed )

	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampn, 0, material, width, false )
	local ctable = {
		Type = "Hydraulic",
		pl = pl,
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		Length1 = Length1,
		Length2 = Length2,
		width = width,
		key = key,
		fixed = fixed,
		fwd_speed = speed,
		bwd_speed = speed,
		toggle = true,
		material = material,
		ConstraintSystem = System
	}
	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	if Constraint and Constraint ~= rope then

		if fixed == 1 then
			local slider = Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0 )
			slider:SetTable( {} )
			Constraint:DeleteOnRemove( slider )
		end

		local controller = ents.Create( "gmod_winch_controller" )
		if Length2 > Length1 then
			controller:SetKeyValue( "minlength", Length1 )
			controller:SetKeyValue( "maxlength", Length2 )
		else
			controller:SetKeyValue( "minlength", Length2 )
			controller:SetKeyValue( "maxlength", Length1 )
		end

		controller:SetConstraint( Constraint )
		controller:Spawn()

		Ent1:DeleteOnRemove( controller )
		Ent2:DeleteOnRemove( controller )

		Constraint:DeleteOnRemove( controller )

		numpad.OnDown( pl, key, "HydraulicToggle", controller )

		return Constraint, rope, controller, slider
	else
		return Constraint, rope
	end

end
duplicator.RegisterConstraint( "Hydraulic", Hydraulic, "pl", "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "Length1", "Length2", "width", "key", "fixed", "fwd_speed", "material" )


--[[----------------------------------------------------------------------
	Muscle( ... )
	Creates a Muscle constraint
------------------------------------------------------------------------]]
local function Muscle( pl, Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, Length1, Length2, width, key, fixed, period, amplitude, starton, material )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if Phys1 == Phys2 then return false end

	local const, dampn = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, fixed )

	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampn, 0, material, width, false )
	if not Constraint then return false end

	local ctable = {
		Type = "Muscle",
		pl = pl,
		Ent1 = Ent1,
		Ent2 = Ent2,
		Bone1 = Bone1,
		Bone2 = Bone2,
		LPos1 = LPos1,
		LPos2 = LPos2,
		Length1 = Length1,
		Length2 = Length2,
		width = width,
		key = key,
		fixed = fixed,
		period = period,
		amplitude = amplitude,
		toggle = true,
		starton = starton,
		material = material,
		ConstraintSystem = System
	}
	Constraint:SetTable( ctable )
	Constraint:CallOnRemove("OnRemove", onRemoveConstraint)

	local slider = nil

	if fixed == 1 then
		slider = Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0 )
		slider:SetTable( {} ) -- ??
		Constraint:DeleteOnRemove( slider )
	end

	local controller = ents.Create( "gmod_winch_controller" )
	if Length2 > Length1 then
		controller:SetKeyValue( "minlength", Length1 )
		controller:SetKeyValue( "maxlength", Length2 )
	else
		controller:SetKeyValue( "minlength", Length2 )
		controller:SetKeyValue( "maxlength", Length1 )
	end
	controller:SetKeyValue( "type", 1 )
	controller:SetConstraint( Constraint )
	controller:Spawn()

	Ent1:DeleteOnRemove( controller )
	Ent2:DeleteOnRemove( controller )

	Constraint:DeleteOnRemove( controller )

	numpad.OnDown( pl, key, "MuscleToggle", controller )

	if starton then
		controller:SetDirection( 1 )
	end

	return Constraint, rope, controller, slider

end
duplicator.RegisterConstraint( "Muscle", Muscle, "pl", "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "Length1", "Length2", "width", "key", "fixed", "period", "amplitude", "starton", "material" )


--[[----------------------------------------------------------------------
	Returns true if this entity has valid constraints
------------------------------------------------------------------------]]
local function HasConstraints( ent )

	if not ent then return false end
	if not ent.Constraints then return false end

	for key, Constraint in pairs( ent.Constraints ) do
		if not IsValid( Constraint ) then ent.Constraints[ key ] = nil
		else return true end
	end

	return false

end


--[[----------------------------------------------------------------------
	Returns this entities constraints table
	This is for the future, because ideally the constraints table will eventually look like this - and we won't have to build it every time.
------------------------------------------------------------------------]]
local function GetTable( ent )

	if not HasConstraints( ent ) then return {} end

	local RetTable = {}

	for key, ConstraintEntity in pairs( ent.Constraints ) do

		local con = {}

		table.Merge( con, ConstraintEntity:GetTable() )

		con.Constraint = ConstraintEntity
		con.Entity = {}

		for i=1, 6 do

			if con[ "Ent"..i ] and ( con[ "Ent"..i ]:IsWorld() or IsValid(con[ "Ent"..i ]) ) then

				con.Entity[ i ] = {}
				con.Entity[ i ].Index = con[ "Ent"..i ]:EntIndex()
				con.Entity[ i ].Entity = con[ "Ent"..i ]
				con.Entity[ i ].Bone = con[ "Bone"..i ]
				con.Entity[ i ].LPos = con[ "LPos"..i ]
				con.Entity[ i ].WPos = con[ "WPos"..i ]
				con.Entity[ i ].Length = con[ "Length"..i ]
				con.Entity[ i ].World = con[ "Ent"..i ]:IsWorld()

			end

		end

		table.insert( RetTable, con )

	end

	return RetTable

end

--[[----------------------------------------------------------------------
	Make this entity forget any constraints it knows about
------------------------------------------------------------------------]]
function constraint.ForgetConstraints( ent )

	ent.Constraints = {}

end


--[[----------------------------------------------------------------------
	Returns a list of constraints, by name
------------------------------------------------------------------------]]
function constraint.FindConstraints( ent, name )

	local ConTable = GetTable( ent )

	local Found = {}

	for k, con in ipairs( ConTable ) do

		if con.Type == name then
			table.insert( Found, con )
		end

	end

	return Found

end

--[[----------------------------------------------------------------------
	Returns the first constraint found by name
------------------------------------------------------------------------]]
function constraint.FindConstraint( ent, name )

	local ConTable = GetTable( ent )

	for k, con in ipairs( ConTable ) do

		if con.Type == name then
			return con
		end

	end

	return nil

end

--[[----------------------------------------------------------------------
	Returns the first constraint found by name
------------------------------------------------------------------------]]
function constraint.FindConstraintEntity( ent, name )

	local ConTable = GetTable( ent )

	for k, con in ipairs( ConTable ) do

		if con.Type == name then
			return con.Constraint
		end

	end

	return NULL

end

--[[----------------------------------------------------------------------
	Returns a table of all the entities constrained to ent
------------------------------------------------------------------------]]
local function GetAllConstrainedEntities( ent, ResultTable )

	local ResultTable = ResultTable or {}

	if not IsValid( ent ) then return end
	if ResultTable[ ent ] then return end

	ResultTable[ ent ] = ent

	local ConTable = GetTable( ent )

	for k, con in ipairs( ConTable ) do

		for EntNum, Ent in pairs( con.Entity ) do
			GetAllConstrainedEntities( Ent.Entity, ResultTable )
		end

	end

	return ResultTable

end


--[[----------------------------------------------------------------------
	Override existing constraint.* funcs with new ones

	The following functions are localised within this script to improve
	performance since they are used within the script.
	Those not listed are created as global instead.
------------------------------------------------------------------------]]
constraint.AddConstraintTable = AddConstraintTable
constraint.AddConstraintTableNoDelete = AddConstraintTableNoDelete
constraint.CanConstrain = CanConstrain
constraint.CreateKeyframeRope = CreateKeyframeRope
constraint.CreateStaticAnchorPoint = CreateStaticAnchorPoint
constraint.Find = Find
constraint.GetAllConstrainedEntities = GetAllConstrainedEntities
constraint.GetTable = GetTable
constraint.HasConstraints = HasConstraints
constraint.RemoveAll = RemoveAll

-- Constraints
constraint.AdvBallsocket = AdvBallsocket
constraint.Axis = Axis
constraint.Ballsocket = Ballsocket
constraint.Elastic = Elastic
constraint.Hydraulic = Hydraulic
constraint.Keepupright = Keepupright
constraint.Motor = Motor
constraint.Muscle = Muscle
constraint.NoCollide = NoCollide
constraint.Pulley = Pulley
constraint.Rope = Rope
constraint.Slider = Slider
constraint.Weld = Weld
constraint.Winch = Winch