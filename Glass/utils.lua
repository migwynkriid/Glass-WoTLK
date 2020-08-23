local Core, _, Utils, Object = unpack(select(2, ...))

-- Utility functions

---
-- Print to VDT
Utils.print = function(str, t)
  if _G.ViragDevTool_AddData then
    _G.ViragDevTool_AddData(t, str)
  else
    -- Buffer print messages until ViragDevTool loads
    table.insert(Core.printBuffer, {str, t})
  end
end


function Object:New(template)
	template     = template or self;
	local newObj = setmetatable({}, template);
	local mt     = getmetatable(newObj);
	mt.__index   = template;
	return newObj;
end

function Object:Subclass()
	return setmetatable({}, {__index = self})
end