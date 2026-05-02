if (not LPH_OBFUSCATED) then
    LPH_JIT_MAX = function(...) return ...; end;
end;

do
	local runservice = game:GetService("RunService");
    local players = game:GetService("Players");

    local localplayer = players.LocalPlayer or players:GetPropertyChangedSignal("LocalPlayer"):Wait() and players.LocalPlayer;
    local character = localplayer.Character or localplayer.CharacterAdded:Wait();
    local humanoidrootpart = character:WaitForChild("HumanoidRootPart");
    local humanoid = character:WaitForChild("Humanoid");

    local clientcframe = humanoidrootpart.CFrame;
	local typeofcache = typeof;
	local tickcache = tick;
	local renderstepped = runservice.RenderStepped;
	local connection, currentlooptype, cframecallback, currentactive;
	local stopspoofing, executing = false, false;
	local activespoofs, registeredspoofs, persistentloops = {}, {}, {};

	local function oncharacter(char)
		character = char;
		humanoid = char:WaitForChild("Humanoid");
		humanoidrootpart = char:WaitForChild("HumanoidRootPart");
		clientcframe = humanoidrootpart.CFrame;
	end;

	if localplayer.Character then
		oncharacter(localplayer.Character);
	end;

	localplayer.CharacterAdded:Connect(oncharacter);

	local mt = getrawmetatable(game);
	local originalindex = mt.__index;
	setreadonly(mt, false);

	mt.__index = newcclosure(function(self, property)
		if (not checkcaller() and self == humanoidrootpart and property == "CFrame" and isspoofing) then
			return clientcframe;
		end;
		return originalindex(self, property);
	end);

	setreadonly(mt, true);

	local looptypes = {
		heartbeat = runservice.Heartbeat,
		renderstepped = runservice.RenderStepped,
		stepped = runservice.Stepped
	};

	local function evaluatecurrent()
		local best;
		for _, v in ipairs(activespoofs) do
			if not best then
				best = v;
			else
				if v.priority > best.priority then
					best = v;
				elseif v.priority == best.priority and v.timestamp < best.timestamp then
					best = v;
				end;
			end;
		end;
		currentactive = best;
	end;

	local function refreshconnection()
		if not currentactive then
			if connection then
				connection:Disconnect();
				connection = nil;
				currentlooptype = nil;
			end;
			return;
		end;
		
		local looptype = currentactive.looptype;
		if connection and currentlooptype == looptype then
			return;
		end;

		if connection then
			connection:Disconnect();
			connection = nil;
		end;

		currentlooptype = looptype;
		local event = looptypes[looptype] or runservice.Heartbeat;

		connection = event:Connect(function()
			if stopspoofing or executing then return; end;
			if not (humanoidrootpart and humanoidrootpart.Parent) then return; end;
			local spoof = currentactive;
			if not spoof then return; end;
			executing = true;

			clientcframe = humanoidrootpart.CFrame;
			local success, result = pcall(spoof.callback, clientcframe);
			if success and result and typeofcache(result) == "CFrame" then
				isspoofing = true;
				local target = result;

				for _, v in ipairs(activespoofs) do
					if v ~= spoof and v.ignore_priority then
						local ok, res = pcall(v.callback, clientcframe);
						if ok and res and typeofcache(res) == "CFrame" then
							target = target * res;
						end;
					end;
				end;

                if spoof.direction then
                    local pos = clientcframe.Position + target.Position;
                    target = CFrame.fromMatrix(pos, result.RightVector, result.UpVector, result.LookVector);
                end;

				humanoidrootpart.CFrame = target;
				renderstepped:Wait();
				humanoidrootpart.CFrame = clientcframe;
				isspoofing = false;

				if cframecallback then
                    cframecallback(target);
                end;

			elseif success then
				if cframecallback then
					cframecallback(clientcframe);
				end;
			else
				warn(("callback error [%s]: %s"):format(spoof.name, tostring(result)));
			end;

			executing = false;
		end);
	end;

	serverposition = function(looptype, logicname, targetlogic, priority, direction, ignore_priority)
		if typeofcache(logicname) ~= "string" then
			warn("invalid logic name");
			return;
		end;
		
		if registeredspoofs[logicname] then
			warn("logic already registered: " .. logicname);
			return;
		end;
		
		if typeofcache(targetlogic) ~= "function" then
			warn("invalid callback for: " .. logicname);
			return;
		end;
		
		if priority ~= nil and typeofcache(priority) ~= "number" then
			warn("invalid priority for: " .. logicname);
			return;
		end;
		
		if typeofcache(looptype) ~= "string" then
			warn("invalid looptype for: " .. logicname);
			return;
		end;

		local lt = looptype:lower();
		registeredspoofs[logicname] = {
			priority = priority or 0,
			timestamp = tickcache(),
			callback = targetlogic,
			looptype = lt,
			name = logicname,
			direction = direction == true,
			ignore_priority = (direction == true) and (ignore_priority == true),
		};
	end;

	setrunning = function(logicname, booleanref, persistent)
		local spoofdata = registeredspoofs[logicname];
		if not spoofdata then
			warn("invalid name: " .. tostring(logicname));
			return;
		end;

		local function applystatus(s)
			local status = s;
			if typeofcache(s) == "function" then
				status = s();
			end;

			if status == true then
				for _, v in ipairs(activespoofs) do
					if v.name == logicname then
						return;
					end;
				end;

				table.insert(activespoofs, spoofdata);
				if not currentactive then
					currentactive = spoofdata;
				else
					if spoofdata.priority > currentactive.priority or (spoofdata.priority == currentactive.priority and spoofdata.timestamp < currentactive.timestamp) then
						currentactive = spoofdata;
					end;
				end;
				refreshconnection();
			else
				local removedcurrent = false;
				for i, v in ipairs(activespoofs) do
					if v.name == logicname then
						if v == currentactive then
							removedcurrent = true;
						end;
						table.remove(activespoofs, i);
						break;
					end;
				end;
				if removedcurrent then
					evaluatecurrent();
				end;
				refreshconnection();
			end;
		end;

		applystatus(booleanref);
		if persistent then
			persistentloops[logicname] = persistentloops[logicname] or {};
			persistentloops[logicname].paused = false;
			persistentloops[logicname].getter = booleanref;
			if not persistentloops[logicname].connection then
				persistentloops[logicname].connection = runservice.Heartbeat:Connect(LPH_JIT_MAX(function()
					local loop = persistentloops[logicname];
					if not loop.paused then
						local desired;
						if typeofcache(loop.getter) == "function" then
							desired = loop.getter();
						else
							desired = loop.getter;
						end;
						if desired ~= getrunning(logicname) then
							applystatus(loop.getter);
						end;
					end;
				end));
			end;
		end;
	end;

	getrunning = function(logicname)
		if not registeredspoofs[logicname] then
			return false;
		end;
		for _, v in ipairs(activespoofs) do
			if v.name == logicname then
				return true;
			end;
		end;
		return false;
	end;

	resetcframe = function()
		stopspoofing = true;
		isspoofing = false;
		executing = false;

		if humanoidrootpart and clientcframe then
			humanoidrootpart.CFrame = clientcframe;
		end;

		for name, _ in pairs(registeredspoofs) do
			for _, v in ipairs(activespoofs) do
				if v.name == name then
					table.remove(activespoofs, _);
					break;
				end;
			end;
			if persistentloops[name] then
				persistentloops[name].paused = true;
			end;
		end;

		currentactive = nil;
		if connection then
			connection:Disconnect();
			connection = nil;
			currentlooptype = nil;
		end;
		stopspoofing = false;
	end;

	clearspoofs = function()
		for _, v in pairs(persistentloops) do
			if v.connection then
				v.connection:Disconnect();
			end;
		end;

		activespoofs = {};
		registeredspoofs = {};
		persistentloops = {};
		currentactive = nil;
		if connection then
			connection:Disconnect();
			connection = nil;
			currentlooptype = nil;
		end;
	end;

	retrieve_position = function(callback)
		if (typeof(callback) ~= "function") then
			warn("invalid callback for retrieve_position");
			return;
		end;
		cframecallback = LPH_JIT_MAX(function(cf)
			local is_spoofing = cf ~= clientcframe and currentactive and currentactive.name ~= "exclude";
			callback(cf, is_spoofing);
		end);
	end;
end;
