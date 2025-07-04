local AggroedCondition = require('cylibs/conditions/aggroed')
local ConditionalCondition = require('cylibs/conditions/conditional')
local Disengage = require('cylibs/battle/disengage')
local DisposeBag = require('cylibs/events/dispose_bag')
local Distance = require('cylibs/conditions/distance')
local Engage = require('cylibs/battle/engage')
local Target = require('cylibs/battle/target')
local GambitTarget = require('cylibs/gambits/gambit_target')
local IsAssistTargetCondition = require('cylibs/conditions/is_assist_target')
local PartyClaimedCondition = require('cylibs/conditions/party_claimed')
local TargetMismatchCondition = require('cylibs/conditions/target_mismatch')
local UnclaimedCondition = require('cylibs/conditions/unclaimed')
local RunToLocation = require('cylibs/actions/runtolocation')

local Gambiter = require('cylibs/trust/roles/gambiter')
local Attacker = setmetatable({}, {__index = Gambiter })
Attacker.__index = Attacker
Attacker.__class = "Attacker"

state.AutoEngageMode = M{['description'] = 'Auto Engage Mode', 'Off', 'Always', 'Mirror', 'KiteAssist'}
state.AutoEngageMode:set_description('Off', "Manually engage and disengage.")
state.AutoEngageMode:set_description('Always', "Automatically engage when targeting a claimed mob.")
state.AutoEngageMode:set_description('Mirror', "Mirror the engage status of the party member you are assisting.")
state.AutoEngageMode:set_description('KiteAssist', "Attack the mob targeted by the assigned kiter, even if not engaged.")

function Attacker.new(action_queue)
    local self = setmetatable(Gambiter.new(action_queue, { Gambits = L{} }, L{ state.AutoEngageMode, state.AutoPullMode }), Attacker)

    self.dispose_bag = DisposeBag.new()
    self:set_attacker_settings({})
    self.follow_target_distance = 3 -- default follow distance in yalms
    self.kiter_name = nil

    return self
end

function Attacker:destroy()
    Gambiter.destroy(self)

    self.dispose_bag:destroy()
end

function Attacker:set_kiter(name)
    self.kiter_name = name
end

function Attacker:handle_kite_assist_command(kiter_name)
    self:set_kiter(kiter_name)
    state.AutoEngageMode:set('KiteAssist')
end

function Attacker:on_add()
    Gambiter.on_add(self)

    self.dispose_bag:add(self:get_party():on_party_target_change():addAction(function(_, _)
        self:check_gambits()
        self:check_and_follow_target()
    end), self:get_party():on_party_target_change())
    
    self.dispose_bag:add(windower.register_event('time change', function()
        if windower.ffxi.get_player().status == 1 then -- If engaged
            self:check_and_follow_target()
        end
    end))

end

function Attacker:target_change(target_index)
    Gambiter.target_change(self, target_index)

    self:check_gambits()
    self:check_and_follow_target()
end

function Attacker:set_follow_target_distance(distance)
    self.follow_target_distance = distance or 3
end

function Attacker:check_and_follow_target()

    local target = windower.ffxi.get_mob_by_target('t')
    if target and target.valid_target and target.hpp > 0 then
        local player = windower.ffxi.get_mob_by_index(windower.ffxi.get_player().index)
        if player then
            local dx = target.x - player.x
            local dy = target.y - player.y
            local dz = target.z - player.z
            local dist3d = math.sqrt(dx*dx + dy*dy + dz*dz)
            -- Use windower follow instead of RunToLocation
            if dist3d > self.follow_target_distance then
                windower.send_command('/follow ' .. target.name)
            elseif dist3d <= self.follow_target_distance then
                windower.send_command('/follow')  -- Stop following when close enough
            end
        end
    end
end

function Attacker:set_attacker_settings(_)
    local gambit_settings = {
        Gambits = L{

            Gambit.new(GambitTarget.TargetType.Enemy, L{
                GambitCondition.new(ModeCondition.new('AutoEngageMode', 'Always'), GambitTarget.TargetType.Self),
                GambitCondition.new(StatusCondition.new('Idle'), GambitTarget.TargetType.Self),
                GambitCondition.new(MaxDistanceCondition.new(30), GambitTarget.TargetType.Enemy),
                GambitCondition.new(AggroedCondition.new(), GambitTarget.TargetType.Enemy),
                GambitCondition.new(ConditionalCondition.new(L{ UnclaimedCondition.new(), PartyClaimedCondition.new(true) }, Condition.LogicalOperator.Or), GambitTarget.TargetType.Enemy),
                GambitCondition.new(ValidTargetCondition.new(alter_ego_util.untargetable_alter_egos()), GambitTarget.TargetType.Enemy),
            }, Engage.new(), GambitTarget.TargetType.Enemy),
            Gambit.new(GambitTarget.TargetType.Enemy, L{
                GambitCondition.new(ModeCondition.new('AutoEngageMode', 'Mirror'), GambitTarget.TargetType.Self),
                GambitCondition.new(IsAssistTargetCondition.new(), GambitTarget.TargetType.Ally),
                GambitCondition.new(StatusCondition.new('Engaged'), GambitTarget.TargetType.Ally),
                GambitCondition.new(StatusCondition.new('Idle'), GambitTarget.TargetType.Self),
                GambitCondition.new(MaxDistanceCondition.new(30), GambitTarget.TargetType.Enemy),
                GambitCondition.new(ConditionalCondition.new(L{ UnclaimedCondition.new(), PartyClaimedCondition.new(true) }, Condition.LogicalOperator.Or), GambitTarget.TargetType.Enemy),
                GambitCondition.new(ValidTargetCondition.new(alter_ego_util.untargetable_alter_egos()), GambitTarget.TargetType.Enemy),
            }, Engage.new(), GambitTarget.TargetType.Enemy),
            Gambit.new(GambitTarget.TargetType.Self, L{
                GambitCondition.new(ModeCondition.new('AutoEngageMode', 'Mirror'), GambitTarget.TargetType.Self),
                GambitCondition.new(IsAssistTargetCondition.new(), GambitTarget.TargetType.Ally),
                GambitCondition.new(StatusCondition.new('Idle'), GambitTarget.TargetType.Ally),
                GambitCondition.new(StatusCondition.new('Engaged'), GambitTarget.TargetType.Self),
            }, Disengage.new(), GambitTarget.TargetType.Self),
            Gambit.new(GambitTarget.TargetType.Enemy, L{
                GambitCondition.new(NotCondition.new(L{ ModeCondition.new('PullActionMode', 'Target') }), GambitTarget.TargetType.Self),
                GambitCondition.new(StatusCondition.new('Idle'), GambitTarget.TargetType.Self),
                GambitCondition.new(TargetMismatchCondition.new(), GambitTarget.TargetType.Self),
            }, Target.new(), GambitTarget.TargetType.Self), -- TODO: should I also remove aggroed condition from this??
            Gambit.new(GambitTarget.TargetType.Enemy, L{
                GambitCondition.new(ModeCondition.new('AutoEngageMode', 'KiteAssist'), GambitTarget.TargetType.Self),
                -- Always engage the mob targeted by the kiter, regardless of engagement status
                GambitCondition.new(StatusCondition.new('Idle'), GambitTarget.TargetType.Self),
                GambitCondition.new(MaxDistanceCondition.new(30), GambitTarget.TargetType.Enemy),
                GambitCondition.new(ValidTargetCondition.new(alter_ego_util.untargetable_alter_egos()), GambitTarget.TargetType.Enemy),
            }, Engage.new(), GambitTarget.TargetType.Enemy),
        }
    }

    for gambit in gambit_settings.Gambits:it() do
        gambit.conditions = gambit.conditions:filter(function(condition)
            return condition:is_editable()
        end)
        local conditions = self:get_default_conditions(gambit)
        for condition in conditions:it() do
            condition:set_editable(false)
            gambit:addCondition(condition)
        end
    end

    gambit_settings.Gambits = L{
        -- we do not want IsAggroedCondition here
        Gambit.new(GambitTarget.TargetType.Self, L{
            GambitCondition.new(StatusCondition.new('Engaged'), GambitTarget.TargetType.Self),
            GambitCondition.new(Distance.new(30, Condition.Operator.GreaterThanOrEqualTo), GambitTarget.TargetType.CurrentTarget),
        }, Disengage.new(), GambitTarget.TargetType.Self),
        Gambit.new(GambitTarget.TargetType.Enemy, L{
            GambitCondition.new(StatusCondition.new('Engaged'), GambitTarget.TargetType.Self),
            GambitCondition.new(TargetMismatchCondition.new(), GambitTarget.TargetType.Self),
        }, Engage.new(), GambitTarget.TargetType.Self),
    } + gambit_settings.Gambits

    self:set_gambit_settings(gambit_settings)
end

function Attacker:get_default_conditions(gambit)
    local conditions = L{
        GambitCondition.new(AggroedCondition.new(), GambitTarget.TargetType.Enemy),
    }
    return conditions:map(function(condition)
        if condition.__type ~= GambitCondition.__type then
            return GambitCondition.new(condition, GambitTarget.TargetType.Self)
        end
        return condition
    end)
end

function Attacker:get_cooldown()
    return 1
end

function Attacker:allows_multiple_actions()
    return false
end

function Attacker:get_type()
    return "attacker"
end

function Attacker:allows_duplicates()
    return false
end

return Attacker