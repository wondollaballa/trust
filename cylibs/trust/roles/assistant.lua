local DisposeBag = require('cylibs/events/dispose_bag')

local Assistant = setmetatable({}, {__index = Role })
Assistant.__index = Assistant
Assistant.__class = "Assistant"

state.AutoAssistantMode = M{['description'] = 'Assistant Mode', 'Off', 'Auto', 'KiteAssist'}
state.AutoAssistantMode:set_description('Auto', "See extra information on the current mob.")
state.AutoAssistantMode:set_description('KiteAssist', "Direct trusts to attack the mob you select, even if you are not engaged.")

function Assistant.new(action_queue, watch_list)
    local self = setmetatable(Role.new(action_queue), Assistant)

    self.watch_list = watch_list or S{}
    self.dispose_bag = DisposeBag.new()
    self.kite_target_id = nil

    return self
end

function Assistant:destroy()
    Role.destroy(self)

    self.dispose_bag:destroy()
end

function Assistant:on_add()
    Role.on_add(self)

    self:add_ability_name('Uproot')
end

function Assistant:target_change(target_index)
    Role.target_change(self, target_index)

    logger.notice(self.__class, 'target_change', 'reset')

    self.dispose_bag:dispose()

    if self:get_target() then
        self.dispose_bag:add(self:get_target():on_tp_move_finish():addAction(function(m, monster_ability_name, _, _)
            if state.AutoAssistantMode.value == 'Off' then
                return
            end
            if self.watch_list:contains(monster_ability_name) then
                self:get_party():add_to_chat(self:get_party():get_player(), "Heads up, "..m:get_name().." just used "..monster_ability_name.."!")
            end
        end, self:get_target():on_tp_move_finish()))
    end
end

function Assistant:add_ability_name(ability_name)
    self.watch_list:add(ability_name)
end

function Assistant:remove_ability_name(ability_name)
    self.watch_list:remove(ability_name)
end

function Assistant:allows_duplicates()
    return false
end

function Assistant:get_type()
    return "assistant"
end

-- New: Handle the kite assist command
function Assistant:handle_kite_assist_command()
    local mob = windower.ffxi.get_mob_by_target('t')
    if mob and mob.valid_target and mob.hpp > 0 then
        self.kite_target_id = mob.id
        state.AutoAssistantMode:set('KiteAssist')
        self:get_party():add_to_chat(self:get_party():get_player(), "KiteAssist: Trusts will now focus on "..mob.name..".")
        -- Notify attackers to update their kite target (if needed)
        -- This assumes attackers check for this mode and kite_target_id
        self:trigger_kite_assist()
    else
        self:get_party():add_to_chat(self:get_party():get_player(), "No valid mob targeted for KiteAssist.")
    end
end

-- New: Notify attackers to move to the kite target
function Assistant:trigger_kite_assist()
    -- This is a stub; actual implementation may use IPC or shared state
    -- Example: If you have a reference to attacker roles, call their handler:
    -- for _, role in pairs(self:get_party():get_roles_by_type("attacker")) do
    --     role:handle_kite_assist_command(self.kite_target_id)
    -- end
end

return Assistant