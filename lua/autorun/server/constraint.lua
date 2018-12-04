local MaxConstraints = 100


--[[----------------------------------------------------------------------
	CreateConstraintSystem
------------------------------------------------------------------------]]
local function CreateConstraintSystem()

	local System = ents.Create("phys_constraintsystem")
		System:SetKeyValue( "additionaliterations", GetConVarNumber( "gmod_physiterations" ) )
		System:Spawn()
		System:Activate()

	System.NumConstraints = 0

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

		if Sys1.NumConstraints < MaxConstraints and Sys1.NumConstraints >= Sys2.NumConstraints then
			System = Sys1
		elseif Sys2.NumConstraints < MaxConstraints and Sys2.NumConstraints >= Sys1.NumConstraints then
			System = Sys2
		else
			System = CreateConstraintSystem()
		end

	elseif IsValid(Ent1.ConstraintSystem) then

		if Ent1.ConstraintSystem.NumConstraints < MaxConstraints then
			System = Ent1.ConstraintSystem
		else
			System = CreateConstraintSystem()
		end

	elseif IsValid(Ent2.ConstraintSystem) then

		if Ent2.ConstraintSystem.NumConstraints < MaxConstraints then
			System = Ent2.ConstraintSystem
		else
			System = CreateConstraintSystem()
		end

	else
		System = CreateConstraintSystem()
	end


	if not Ent1.ConstraintSystem then Ent1.ConstraintSystem = System end
	if not Ent2.ConstraintSystem then Ent2.ConstraintSystem = System end

	System.NumConstraints = System.NumConstraints+1

	return System

end

--[[----------------------------------------------------------------------
	AddConstraintTable( Ent, Constraint, Ent2 )
	Stores info about the constraints on the entity's table
------------------------------------------------------------------------]]
local function AddConstraintTable( Ent, Constraint, Ent2 )

	if not IsValid( Constraint ) then return end

	if IsValid(Ent) then
		Ent.Constraints = Ent.Constraints or {}
		Constraint.Ent1Key = table.insert( Ent.Constraints, Constraint )
		
		Ent:DeleteOnRemove(Constraint)
	end

	if Ent2 and Ent2 ~= Ent then
		Ent2.Constraints = Ent2.Constraints or {}
		Constraint.Ent2Key = table.insert( Ent2.Constraints, Constraint )
		
		Ent2:DeleteOnRemove(Constraint)
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
		Constraint.Ent1Key = table.insert( Ent.Constraints, Constraint )
	end

	if Ent2 and Ent2 ~= Ent then
		Ent2.Constraints = Ent2.Constraints or {}
		Constraint.Ent2Key = table.insert( Ent2.Constraints, Constraint )
	end

end

--[[----------------------------------------------------------------------
	OnRemoveConstraint(Constraint)
	Automatically called when a constraint is removed
------------------------------------------------------------------------]]
local function OnRemoveConstraint(Constraint)

	if not IsValid(Constraint) then return end

	local System = Constraint.ConstraintSystem
	local E1 = Constraint.Ent1
	local E2 = Constraint.Ent2

	if IsValid(System) then -- NoCollides/KeepUpright don't have constraint systems
		System.NumConstraints = System.NumConstraints-1

		if System.NumConstraints == 0 then
			if IsValid(E1) then E1.ConstraintSystem = nil end
			if IsValid(E2) then E2.ConstraintSystem = nil end

			System:Remove()
		end
	end


	if IsValid(E1) then
		E1.Constraints[Constraint.Ent1Key] = nil

		if not next(E1.Constraints) then E1.Constraints = nil end
	end

	if IsValid(E2) then
		E2.Constraints[Constraint.Ent2Key] = nil

		if not next(E2.Constraints) then E2.Constraints = nil end
	end
end

--[[----------------------------------------------------------------------
	local Constraint = CreateConstraint( Type, Ent1, Ent2, Bone1, Bone2, EntsDeleteConstraintWhenRemoved, NoConstraintSystem )
	Should be called in order to create a constraint

	Type = constraint class eg. "phys_constraint"
	EntsDeleteConstraintWhenRemoved:
		nil  = don't add to constraint table
		true = ents assigned to constraint delete when constraint is removed
		false = ents are not deleted when constraint is removed
	NoConstraintSystem:
		For constraints that either don't need a constraint system (Non-entity based constraints)
		or constraints that solve in a single interation (nocollides)
------------------------------------------------------------------------]]
local function CreateConstraint( Type, Ent1, Ent2, Bone1, Bone2, EntsDeleteConstraintWhenRemoved, NoConstraintSystem )

	local System = nil

	-- NoCollides do not have constraint systems
	if not NoConstraintSystem then
		System = FindOrCreateConstraintSystem( Ent1, Ent2 )

		SetPhysConstraintSystem( System ) -- Any constraints called after this call will use this system
	end

	local Constraint = ents.Create(Type)

	if IsValid(Constraint) then

		-- Basic required information
		Constraint.ConstraintSystem = System
		Constraint.Ent1 = Ent1
		Constraint.Ent2 = Ent2
		Constraint.Bone1 = Bone1
		Constraint.Bone2 = Bone2

		Constraint:CallOnRemove("ConstraintCleanConTables", OnRemoveConstraint)

		-- Add constraint to each entities respective constraint table
		if EntsDeleteConstraintWhenRemoved ~= nil then
			if EntsDeleteConstraintWhenRemoved then
				AddConstraintTable(Ent1, Constraint, Ent2)
			else
				AddConstraintTableNoDelete(Ent1, Constraint, Ent2)
			end
		end

	end

	SetPhysConstraintSystem( NULL ) -- Turn off constraint system override

	return Constraint

end

local function SetPhysicsCollisions( Ent, Bool )

	if not IsValid( Ent ) or not IsValid( Ent:GetPhysicsObject() ) then return end

	Ent:GetPhysicsObject():EnableCollisions( Bool )

end

--[[----------------------------------------------------------------------
	RemoveConstraints( Ent, Type )
	Removes all constraints of type from entity
------------------------------------------------------------------------]]
local function RemoveConstraints( Ent, Type )

	if not Ent.Constraints then return end

	local Constraints = Ent.Constraints
	local Count = 0

	for _, Constraint in pairs(Constraints) do
		if Constraint.Type == Type then
			SetPhysicsCollisions(Constraint.Ent1, true)
			SetPhysicsCollisions(Constraint.Ent2, true)

			Constraint:Remove()
			Count = Count+1
		end
	end

	return Count ~= 0, Count

end

--[[----------------------------------------------------------------------
	RemoveAll( Ent )
	Removes all constraints from entity
------------------------------------------------------------------------]]
local function RemoveAll( Ent )

	if not Ent.Constraints then return end

	local Constraints = Ent.Constraints
	local Count = #Constraints

	for _, Constraint in pairs(Constraints) do

		SetPhysicsCollisions(Constraint.Ent1, true)
		SetPhysicsCollisions(Constraint.Ent2, true)

		Constraint:Remove()
	end

	return true, Count

end

--[[----------------------------------------------------------------------
	Find( Ent1, Ent2, Type, Bone1, Bone2 )
	Removes all constraints from entity
------------------------------------------------------------------------]]
local function Find( Ent1, Ent2, Type, Bone1, Bone2 )

	if not Ent1.Constraints or not Ent2.Constraints then return end

	for _, V in pairs( Ent1.Constraints ) do

		if V.Type == Type then
			if  V.Ent1 == Ent1 and V.Ent2 == Ent2 and V.Bone1 == Bone1 and V.Bone2 == Bone2 then
				return v
			end

			if V.Ent2 == Ent1 and V.Ent1 == Ent2 and V.Bone2 == Bone1 and V.Bone1 == Bone2 then
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
	Weld( ... )
	Creates a solid weld constraint
------------------------------------------------------------------------]]
local function Weld( Ent1, Ent2, Bone1, Bone2, forcelimit, nocollide, deleteonbreak )

	if Ent1 == Ent2 and Bone1 == Bone2 then return false end
	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end
	if Find( Ent1, Ent2, "Weld", Bone1, Bone2 ) then return false end -- Multiple welds does not make the constraint stronger
	if Ent1:IsWorld() then Ent1, Ent2 = Ent2, game.GetWorld() end -- Welding props to world instead of world to prop prevents crazy physics


	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	local Constraint = CreateConstraint("phys_constraint", Ent1, Ent2, Bone1, Bone2, true)
	
	if forcelimit then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
	if nocollide then Constraint:SetKeyValue( "spawnflags", 1 ) end
	if deleteonbreak then Ent2:DeleteOnRemove( Ent1 ) end -- Optionally delete Ent1 when the weld is broken... Fixes bug #310

	Constraint:SetPhysConstraintObjects( Phys2, Phys1 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type          = 'Weld'
	Constraint.forcelimit    = forcelimit
	Constraint.nocollide     = nocollide
	Constraint.deleteonbreak = deleteonbreak

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
	local Rope = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, { Length = length + addlength, Collide = 1, Type = rigid and 2 or nil } )

	-- If two separate entities then make a real rope
	if Phys1 ~= Phys2 then

		Constraint = OnStartConstraint("phys_lengthconstraint", Ent1, Ent2, Bone1, Bone2, true)

		Constraint:SetPos( WPos1 )
		Constraint:SetKeyValue( "attachpoint", tostring( WPos2 ) )
		Constraint:SetKeyValue( "minlength", "0.0" )
		Constraint:SetKeyValue( "length", length + addlength )
		
		if forcelimit then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
		if rigid then Constraint:SetKeyValue( "spawnflags", 2 ) end
		
		Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
		Constraint:Spawn()
		Constraint:Activate()

	else
		-- If both ents are the same, return the keyframe rope (Not an actual constraint)
		Constraint, Rope = Rope, nil

	end

	Constraint.Type      = 'Rope'
	Constraint.Ent1      = Ent1
	Constraint.Ent2      = Ent2
	Constraint.Bone1     = Bone1
	Constraint.Bone2     = Bone2
	Constraint.LPos1     = LPos1
	Constraint.LPos2     = LPos2
	Constraint.length    = length
	Constraint.addlength = addlength
	Constraint.width     = width
	Constraint.material  = material
	Constraint.rigid     = rigid

	return Constraint, Rope

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

	if Phys1 == Phys2 then return nil, nil end
	
	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )
	local Rope  = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, { Collide = 1, Type = 0 } )
	local Constraint = OnStartConstraint("phys_spring", Ent1, Ent2, Bone1, Bone2, true )

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

	Constraint.Type = 'Elastic'
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.constant = constant
	Constraint.damping = damping
	Constraint.rdamping = rdamping
	Constraint.material = material
	Constraint.width = width
	Constraint.length = ( WPos1 - WPos2 ):Length()
	Constraint.stretchonly = stretchonly

	return Constraint, Rope
end
duplicator.RegisterConstraint("Elastic", Elastic, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "constant", "damping", "rdamping", "material", "width", "stretchonly")


--[[----------------------------------------------------------------------
	Keepupright( ... )
	Creates a KeepUpright constraint
------------------------------------------------------------------------]]
local function Keepupright( Ent, Ang, Bone, angularlimit )

	if Ent:GetClass() ~= "prop_physics" and Ent:GetClass() ~= "prop_ragdoll" then return false end
	if not CanConstrain( Ent, Bone ) then return false end
	if not angularlimit or angularlimit < 0 then return end

	-- Remove any KU's already on entity
	RemoveConstraints( Ent, "Keepupright" )
	
	local Phys = Ent:GetPhysicsObjectNum(Bone)
	local Constraint = CreateConstraint("phys_keepupright", Ent, nil, nil, nil, true )
	
	Constraint:SetAngles( Ang )
	Constraint:SetKeyValue( "angularlimit", angularlimit )
	Constraint:SetPhysConstraintObjects( Phys, Phys )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Keepupright"
	Constraint.Ang = Ang
	Constraint.Bone = Bone -- Inconsistency: all other constraints refer to their bones as Bone1 and Bone2
	Constraint.angularlimit = angularlimit

	-- This is a hack to keep the KeepUpright context menu in sync..
	Ent:SetNWBool( "IsUpright", true )

	return Constraint

end
duplicator.RegisterConstraint( "Keepupright", Keepupright, "Ent1", "Ang", "Bone", "angularlimit" )


local function CreateStaticAnchorPoint( Pos ) -- Only needed if Slider constraints exist

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
local function Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, width, material, NoTable )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )

	if Phys1 == Phys2 then return end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )
	local StaticAnchor = nil

	-- Attaching a slider to the world makes it really sucks so we make a prop and attach to that.
	if Ent1:IsWorld() then
		Ent1, Phys1, Bone1, LPos1 = CreateStaticAnchorPoint( WPos1 )
		StaticAnchor = Ent1
	end

	if Ent2:IsWorld() then
		Ent2, Phys2, Bone2, LPos2 = CreateStaticAnchorPoint( WPos2 )
		StaticAnchor = Ent2
	end

	local Rope = CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, Ent2, LPos2, Bone2, { Collide = 0, Type = 2, Subdiv = 1, } )
	local Constraint = CreateConstraint("phys_slideconstraint", Ent1, Ent2, Bone1, Bone2, NoTable and nil or true)

	if NoTable then Constraint:RemoveCallOnRemove("ConstraintCleanConTables") end

	Constraint:SetPos( WPos1 )
	Constraint:SetKeyValue( "slideaxis", tostring( WPos2 ) )
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Slider"
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.width = width
	Constraint.material = material

	-- If we have a static anchor delete it when we the slider is removed
	if StaticAnchor then Constraint:DeleteOnRemove( StaticAnchor ) end

	return Constraint, Rope

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
	
	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if LocalAxis then WPos2 = Phys1:LocalToWorld( LocalAxis ) end -- If we have a LocalAxis, use that

	-- Pass nil to not create a constraint table (if DontAddTable is true)
	local Constraint = CreateConstraint("phys_hinge", Ent1, Ent2, Bone1, Bone2, DontAddTable and nil or true)

	
	Constraint:SetPos( WPos1 )
	Constraint:SetKeyValue( "hingeaxis", tostring( WPos2 ) )
	
	if forcelimit and forcelimit > 0 then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
	if torquelimit and torquelimit > 0 then Constraint:SetKeyValue( "torquelimit", torquelimit ) end
	if friction and friction > 0 then Constraint:SetKeyValue( "hingefriction", friction ) end
	if nocollide and nocollide > 0 then Constraint:SetKeyValue( "spawnflags", 1 ) end
	
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Axis"
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.forcelimit = forcelimit
	Constraint.torquelimit = torquelimit
	Constraint.friction = friction
	Constraint.nocollide = nocollide
	Constraint.LocalAxis = Phys1:WorldToLocal( WPos2 )

	if DontAddTable then Constraint:RemoveCallOnRemove("ConstraintCleanConTables") end

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
	
	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )
	local Constraint = CreateConstraint("phys_ragdollconstraint", Ent1, Ent2, Bone1, Bone2, true)
	
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
	
	local flags = 0
	if onlyrotation and onlyrotation > 0 then flags = 2 end
	if nocollide and nocollide > 0 then flags = flags + 1 end

	Constraint:SetKeyValue( "spawnflags", flags )
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "AdvBallsocket"
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.forcelimit = forcelimit
	Constraint.torquelimit = torquelimit
	Constraint.xmin = xmin
	Constraint.ymin = ymin
	Constraint.zmin = zmin
	Constraint.xmax = xmax
	Constraint.ymax = ymax
	Constraint.zmax = zmax
	Constraint.xfric = xfric
	Constraint.yfric = yfric
	Constraint.zfric = zfric
	Constraint.onlyrotation = onlyrotation
	Constraint.nocollide = nocollide
	Constraint.ConstraintSystem = System

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

	if Find( Ent1, Ent2, "NoCollide", Bone1, Bone2 ) then return false end -- Don't allow redundant nocollides
	
	local Constraint = CreateConstraint("logic_collision_pair", Ent1, Ent2, Bone1, Bone2, true, false) -- Pass false to NOT assign to a constraint system
	
	Constraint:SetKeyValue( "startdisabled", 1 )
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()
	Constraint:Input( "DisableCollisions", nil, nil, nil )

	Constraint.Type = "NoCollide"

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

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )

	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	if LocalAxis then WPos2 = Phys1:LocalToWorld( LocalAxis ) end

	-- The true at the end stops it adding the axis table to the entity's count stuff.
	local Axis = Axis( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0, 0, friction, nocollide, LocalAxis, true )
	local Constraint = CreateConstraint("phys_torque", Ent1, Ent2, Bone1, Bone2, false)
	
	Constraint:SetPos( WPos1 )
	Constraint:SetKeyValue( "axis", tostring( WPos2 ) )
	Constraint:SetKeyValue( "force", torque )
	Constraint:SetKeyValue( "forcetime", forcetime )
	Constraint:SetKeyValue( "spawnflags", 4 )
	Constraint:SetPhysConstraintObjects( Phys1, Phys1 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Motor"
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.friction = friction
	Constraint.torque = torque
	Constraint.forcetime = forcetime
	Constraint.nocollide = nocollide
	Constraint.toggle = toggle
	Constraint.pl = pl
	Constraint.forcelimit = forcelimit
	Constraint.forcescale = 0
	Constraint.direction = direction or 1
	Constraint.is_on = false
	Constraint.numpadkey_fwd = numpadkey_fwd
	Constraint.numpadkey_bwd = numpadkey_bwd
	Constraint.LocalAxis = Phys1:WorldToLocal( WPos2 )

	-- Delete the axis when either object dies
	Ent1:DeleteOnRemove( Axis )
	Ent2:DeleteOnRemove( Axis )

	-- Delete the phys_torque too!
	Axis:DeleteOnRemove( Constraint )
	-- Delete the axis constrain if phys_torque is deleted, with something like Motor tools reload
	Constraint:DeleteOnRemove( Axis )

	if numpadkey_fwd then
		numpad.OnDown( pl, numpadkey_fwd, "MotorControl", Constraint, true, 1 )
		numpad.OnUp( pl, numpadkey_fwd, "MotorControl", Constraint, false, 1 )
	end

	if numpadkey_bwd then
		numpad.OnDown( pl, numpadkey_bwd, "MotorControl", Constraint, true, -1 )
		numpad.OnUp( pl, numpadkey_bwd, "MotorControl", Constraint, false, -1 )
	end

	return Constraint, Axis

end
duplicator.RegisterConstraint( "Motor", Motor, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "friction", "torque", "forcetime", "nocollide", "toggle", "pl", "forcelimit", "numpadkey_fwd", "numpadkey_bwd", "direction", "LocalAxis" )


--[[----------------------------------------------------------------------
	Pulley( ... )
	Creates a pulley constraint
------------------------------------------------------------------------]]
local function Pulley( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, WPos2, WPos3, forcelimit, rigid, width, material )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )
	
	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos4 = Phys2:LocalToWorld( LPos2 )

	local Constraint = CreateConstraint("phys_pulleyconstraint", Ent1, Ent2, Bone1, Bone2, true)
	
	Constraint:SetPos( WPos2 )
	Constraint:SetKeyValue( "position2", tostring( WPos3 ) )
	Constraint:SetKeyValue( "ObjOffset1", tostring( LPos1 ) )
	Constraint:SetKeyValue( "ObjOffset2", tostring( LPos2 ) )
	Constraint:SetKeyValue( "forcelimit", forcelimit )
	Constraint:SetKeyValue( "addlength", ( WPos3 - WPos4 ):Length() )
	
	if rigid then Constraint:SetKeyValue( "spawnflags", 2 ) end
	
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Pulley"
	Constraint.LPos1 = LPos1
	Constraint.LPos4 = LPos2 -- Inconsistency: All other constraints refer to this as LPos2
	Constraint.WPos2 = WPos2
	Constraint.WPos3 = WPos3
	Constraint.forcelimit = forcelimit
	Constraint.rigid = rigid
	Constraint.width = width
	Constraint.material = material
	Constraint.ConstraintSystem = System

	-- Make Ropes
	local World = game.GetWorld()
	local kv = {
		Collide = 1,
		Type = 2,
		Subdiv = 1,
	}

	CreateKeyframeRope( WPos1, width, material, Constraint, Ent1, LPos1, Bone1, World, WPos2, 0, kv )
	CreateKeyframeRope( WPos1, width, material, Constraint, World, WPos3, 0, World, WPos2, 0, kv )
	CreateKeyframeRope( WPos1, width, material, Constraint, World, WPos3, 0, Ent2, LPos2, Bone2, kv )

	return Constraint

end
duplicator.RegisterConstraint( "Pulley", Pulley, "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "WPos2", "WPos3", "forcelimit", "rigid", "width", "material" )


--[[----------------------------------------------------------------------
	Ballsocket( ... )
	Creates a Ballsocket constraint
------------------------------------------------------------------------]]
local function Ballsocket( Ent1, Ent2, Bone1, Bone2, LPos, forcelimit, torquelimit, nocollide )

	if not CanConstrain( Ent1, Bone1 ) then return false end
	if not CanConstrain( Ent2, Bone2 ) then return false end

	local Phys1 = Ent1:GetPhysicsObjectNum( Bone1 )
	local Phys2 = Ent2:GetPhysicsObjectNum( Bone2 )

	if Phys1 == Phys2 then return false end

	local WPos = Phys2:LocalToWorld( LPos )
	local Constraint = CreateConstraint("phys_ballsocket", Ent1, Ent2, Bon1, Bone2, true)
	
	if forcelimit and forcelimit > 0 then Constraint:SetKeyValue( "forcelimit", forcelimit ) end
	if torquelimit and torquelimit > 0 then Constraint:SetKeyValue( "torquelimit", torquelimit ) end
	if nocollide and nocollide > 0 then Constraint:SetKeyValue( "spawnflags", 1 ) end
	
	Constraint:SetPos( WPos )
	Constraint:SetPhysConstraintObjects( Phys1, Phys2 )
	Constraint:Spawn()
	Constraint:Activate()

	Constraint.Type = "Ballsocket"
	Constraint.LPos = LPos
	Constraint.forcelimit = forcelimit
	Constraint.torquelimit = torquelimit
	Constraint.nocollide = nocollide
	Constraint.ConstraintSystem = System
	
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
	
	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	local const, dampen = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, false )
	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampen, 0, material, width, true )

	if not Constraint then return nil, rope end

	Constraint.Type = "Winch"
	Constraint.pl = pl
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.width = width
	Constraint.fwd_bind = fwd_bind
	Constraint.bwd_bind = bwd_bind
	Constraint.fwd_speed = fwd_speed
	Constraint.bwd_speed = bwd_speed
	Constraint.material = material
	Constraint.toggle = toggle

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

	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )

	
	local const, dampn = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, fixed )

	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampn, 0, material, width, false )

	Constraint.Type = "Hydraulic"
	Constraint.pl = pl
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.Length1 = Length1
	Constraint.Length2 = Length2
	Constraint.width = width
	Constraint.key = key
	Constraint.fixed = fixed
	Constraint.fwd_speed = speed
	Constraint.bwd_speed = speed
	Constraint.toggle = true
	Constraint.material = material

	if Constraint then

		if fixed then
			local slider = Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0, true)

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
	
	if Phys1 == Phys2 then return false end

	local WPos1 = Phys1:LocalToWorld( LPos1 )
	local WPos2 = Phys2:LocalToWorld( LPos2 )


	local const, dampn = CalcElasticConsts( Phys1, Phys2, Ent1, Ent2, fixed )

	local Constraint, rope = Elastic( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, const, dampn, 0, material, width, false )
	if not Constraint then return false end

	Constraint.Type = "Muscle"
	Constraint.pl = pl
	Constraint.LPos1 = LPos1
	Constraint.LPos2 = LPos2
	Constraint.Length1 = Length1
	Constraint.Length2 = Length2
	Constraint.width = width
	Constraint.key = key
	Constraint.fixed = fixed
	Constraint.period = period
	Constraint.amplitude = amplitude
	Constraint.toggle = true
	Constraint.starton = starton
	Constraint.material = material
	
	local slider = nil
	if fixed then
		slider = Slider( Ent1, Ent2, Bone1, Bone2, LPos1, LPos2, 0, true )

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

	if starton then controller:SetDirection( 1 ) end

	return Constraint, rope, controller, slider

end
duplicator.RegisterConstraint( "Muscle", Muscle, "pl", "Ent1", "Ent2", "Bone1", "Bone2", "LPos1", "LPos2", "Length1", "Length2", "width", "key", "fixed", "period", "amplitude", "starton", "material" )


--[[----------------------------------------------------------------------
	Returns true if this entity has valid constraints
------------------------------------------------------------------------]]
local function HasConstraints( ent )

	if not ent then return false end
	if not ent.Constraints then return false end

	return true

end

local function GetTableStyle(Constraint)
	local Table = table.Copy(Constraint:GetTable())

	Table.Constraint = Constraint
	Table.Entity = {}

	for I = 1, 6 do
		local Ent = Constraint["Ent"..I]

		if Ent and (IsValid(Ent) or Ent:IsWorld()) then

			Table.Entity[ I ] = {
				Index = Ent:EntIndex(),
				Entity = Ent,
				Bone = Table[ "Bone"..I ],
				LPos = Table[ "LPos"..I ],
				WPos = Table[ "WPos"..I ],
				Length = Table[ "Length"..I ],
				World = Ent:IsWorld()
			}

		end
	end

	return Table
end


--[[----------------------------------------------------------------------
	Returns this entities constraints table
	This is for the future, because ideally the constraints table will eventually look like this - and we won't have to build it every time.
------------------------------------------------------------------------]]
function constraint.GetTable( Ent )
	if not Ent then return {} end
	if not Ent.Constraints then return {} end

	local Table = {}

	for _, Constraint in pairs( Ent.Constraints ) do Table[#Table+1] = GetTableStyle(Constraint) end

	return Table

end

--[[----------------------------------------------------------------------
	Make this entity forget any constraints it knows about
------------------------------------------------------------------------]]
function constraint.ForgetConstraints( Ent )
	Ent.Constraints = {}
end


--[[----------------------------------------------------------------------
	Returns a list of constraints, filtered by type
------------------------------------------------------------------------]]
function constraint.FindConstraints( Ent, Type )

	if not Ent.Constraints then return {} end

	local Found = {}

	for _, Constraint in pairs(Ent.Constraints) do

		if Constraint.Type == Type then
			Found[#Found+1] = GetTableStyle(Constraint)
		end

	end

	return Found

end

--[[----------------------------------------------------------------------
	Returns the first constraint table found by type
------------------------------------------------------------------------]]
function constraint.FindConstraint( Ent, Type )

	if not Ent.Constraints then return nil end

	for _, Constraint in pairs(Ent.Constraints) do
		if Constraint.Type == Type then
			return GetTableStyle(Constraint)
		end
	end

	return nil

end

--[[----------------------------------------------------------------------
	Returns the first constraint entity found by name
------------------------------------------------------------------------]]
function constraint.FindConstraintEntity( Ent, Type )

	if not Ent.Constraints then return NULL end -- Not sure why we're returning NULL instead of nil but ok

	for _, Constraint in pairs(Ent.Constraints) do
		if Constraint.Type == Type then
			return Constraint
		end
	end

	return NULL

end

--[[----------------------------------------------------------------------
	Returns a table of all the entities constrained to ent
------------------------------------------------------------------------]]
local function GetAllConstrainedEntities( Ent, Res )

	if not IsValid(Ent) then return end

	if Res then
		if Res[Ent] then return
		else Res[Ent] = Ent end
	else
		Res = {}
	end


	if Ent.Constraints then
		for _, Constraint in pairs(Ent.Constraints) do
			GetAllConstrainedEntities(Constraint.Ent1, Res)
			GetAllConstrainedEntities(Constraint.Ent2, Res)
		end
	end

	return Res

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
constraint.HasConstraints = HasConstraints
constraint.RemoveAll = RemoveAll

-- New global functions
constraint.OnRemoveConstraint = OnRemoveConstraint
constraint.CreateConstraint = CreateConstraint

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

--[[----------------------------------------------------------------------
	Make wiremod hydraulics compliant with changes
------------------------------------------------------------------------]]

hook.Add("Initialize", "WireHydroOverride", function()
	local LegacyWireHydro = MakeWireHydraulic

	function MakeWireHydraulic(...)
		local Constraint, Rope = LegacyWireHydro(...)

		if IsValid(Constraint) then
			Constraint:CallOnRemove("ConstraintCleanConTables", OnRemoveConstraint)
		end

		return Constraint, Rope
	end
end)
