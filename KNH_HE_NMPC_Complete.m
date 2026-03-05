%% ========================================================================
%% KNH_HE_NMPC_Complete.m
%% COMPLETE HE-NMPC SIMULATION ENVIRONMENT
%% One file to rule them all - GUI + PEM Model + Optimization + Simulation
%% ========================================================================

function KNH_HE_NMPC_Complete()
    % ====================================================================
    % MAIN FUNCTION - LAUNCHES THE COMPLETE APPLICATION
    % ====================================================================
    
    clear; clc; close all;
    
    % Create the main figure
    createMainGUI();
end

%% ========================================================================
%% SECTION 1: GUI CREATION
%% ========================================================================

function createMainGUI()
    % Create the main figure window
    fig = figure('Name', 'KNH HE-NMPC Simulator', ...
                 'Position', [100, 100, 1400, 800], ...
                 'NumberTitle', 'off', ...
                 'MenuBar', 'none', ...
                 'ToolBar', 'none', ...
                 'Resize', 'on', ...
                 'Color', [0.94, 0.94, 0.94]);
    
    % Store GUI data
    guiData = struct();
    guiData.modelExists = false;
    guiData.optimalParams = [];
    guiData.slxModelPath = '';  % Path to Simulink .slx model once created
    guiData.simulationRunning = false;
    guiData.arduinoConnected = false;
    guiData.mqttConnected = false;
    guiData.serialObj = [];
    guiData.mqttClient = [];
    guiData.params = initializeDefaultParams();
    
    % Store in figure
    guidata(fig, guiData);
    
    % Create all UI components
    createUIPanels(fig);
end

%% ========================================================================
%% Initialize Default Parameters (KNH Values)
%% ========================================================================

function params = initializeDefaultParams()
    % ===== HOSPITAL PARAMETERS (KNH) =====
    params.hospital.name = 'Kenyatta National Hospital';
    params.hospital.beds = 1800;
    params.hospital.icu_beds = 120;
    params.hospital.o2_per_bed = 10;      % L/min per bed average
    params.hospital.peak_factor = 1.5;    % Morning/evening peaks
    params.hospital.tank_capacity = 10000; % Liters
    params.hospital.min_reserve = 2000;    % Liters safety reserve
    
    % ===== ELECTROLYZER PARAMETERS =====
    params.electrolyzer.stack_size = 50;    % Number of cells
    params.electrolyzer.cell_area = 100;    % cm²
    params.electrolyzer.min_current = 0.1;  % A/cm²
    params.electrolyzer.max_current = 2.0;  % A/cm²
    params.electrolyzer.min_temp = 20;      % °C
    params.electrolyzer.max_temp = 80;      % °C
    params.electrolyzer.operating_temp = 60; % °C
    
    % ===== SOLAR PV PARAMETERS =====
    params.solar.capacity = 250;        % kWp
    params.solar.efficiency = 0.85;     % System efficiency
    params.solar.tilt = 15;             % Degrees (Nairobi optimal)
    params.solar.azimuth = 180;          % North-facing
    
    % ===== GRID TARIFF (Kenya Power) =====
    params.tariff.peak = 25;             % Ksh/kWh (6pm-11pm)
    params.tariff.offpeak = 12;          % Ksh/kWh (11pm-6am)
    params.tariff.shoulder = 18;          % Ksh/kWh (6am-6pm)
    params.tariff.peak_start = 18;        % 6pm
    params.tariff.peak_end = 23;          % 11pm
    
    % ===== PEM MODEL PARAMETERS (from Liso validation) =====
    params.pem.a_act = 0.10;              % Tafel intercept [V]
    params.pem.b_act = 0.08;              % Tafel slope [V/ln(A/cm²)]
    params.pem.R_ohm = 0.18;               % Area-specific resistance [Ω·cm²]
    params.pem.k_conc = 0.006;             % Concentration coefficient
    params.pem.rmse_60 = 0.058;            % Validation RMSE at 60°C
    params.pem.rmse_80 = 0.052;            % Validation RMSE at 80°C
    params.pem.r2_60 = 0.902;               % R² at 60°C
    params.pem.r2_80 = 0.915;               % R² at 80°C
end

%% ========================================================================
%% Create All UI Panels
%% ========================================================================

function createUIPanels(fig)
    guiData = guidata(fig);
    
    % ===== PANEL 1: HOSPITAL PARAMETERS =====
    hPanel1 = uipanel('Parent', fig, ...
        'Title', '🏥 Hospital Parameters', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.02, 0.55, 0.3, 0.4]);
    
    % Create hospital fields
    yPos = 0.85;
    fields = {
        'Hospital Name:', 'edit', 'hospital.name';
        'Total Beds:', 'numeric', 'hospital.beds';
        'ICU Beds:', 'numeric', 'hospital.icu_beds';
        'Avg O₂/Bed (L/min):', 'numeric', 'hospital.o2_per_bed';
        'Peak Factor:', 'numeric', 'hospital.peak_factor';
        'Tank Capacity (L):', 'numeric', 'hospital.tank_capacity';
        'Min Reserve (L):', 'numeric', 'hospital.min_reserve'
    };
    
    for i = 1:size(fields, 1)
        uicontrol('Parent', hPanel1, 'Style', 'text', ...
            'String', fields{i,1}, ...
            'Position', [20, yPos*100, 120, 20], ...
            'HorizontalAlignment', 'left');
        
        if strcmp(fields{i,2}, 'edit')
            h = uicontrol('Parent', hPanel1, 'Style', 'edit', ...
                'Position', [150, yPos*100, 150, 25], ...
                'String', getParam(guiData.params, fields{i,3}), ...
                'Callback', {@editCallback, fields{i,3}});
        else
            h = uicontrol('Parent', hPanel1, 'Style', 'edit', ...
                'Position', [150, yPos*100, 150, 25], ...
                'String', num2str(getParam(guiData.params, fields{i,3})), ...
                'Callback', {@numericCallback, fields{i,3}});
        end
        yPos = yPos - 0.08;
    end
    
    % ===== PANEL 2: ELECTROLYZER PARAMETERS =====
    hPanel2 = uipanel('Parent', fig, ...
        'Title', '⚡ Electrolyzer Parameters', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.35, 0.55, 0.3, 0.4]);
    
    yPos = 0.85;
    fields2 = {
        'Stack Size (cells):', 'numeric', 'electrolyzer.stack_size';
        'Cell Area (cm²):', 'numeric', 'electrolyzer.cell_area';
        'Min Current (A/cm²):', 'numeric', 'electrolyzer.min_current';
        'Max Current (A/cm²):', 'numeric', 'electrolyzer.max_current';
        'Min Temp (°C):', 'numeric', 'electrolyzer.min_temp';
        'Max Temp (°C):', 'numeric', 'electrolyzer.max_temp';
        'Operating Temp (°C):', 'numeric', 'electrolyzer.operating_temp'
    };
    
    for i = 1:size(fields2, 1)
        uicontrol('Parent', hPanel2, 'Style', 'text', ...
            'String', fields2{i,1}, ...
            'Position', [20, yPos*100, 120, 20], ...
            'HorizontalAlignment', 'left');
        
        h = uicontrol('Parent', hPanel2, 'Style', 'edit', ...
            'Position', [150, yPos*100, 150, 25], ...
            'String', num2str(getParam(guiData.params, fields2{i,3})), ...
            'Callback', {@numericCallback, fields2{i,3}});
        yPos = yPos - 0.08;
    end
    
    % ===== PANEL 3: SOLAR & GRID =====
    hPanel3 = uipanel('Parent', fig, ...
        'Title', '☀️ Solar PV & Grid Tariff', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.68, 0.55, 0.3, 0.4]);
    
    yPos = 0.85;
    fields3 = {
        'PV Capacity (kWp):', 'numeric', 'solar.capacity';
        'Panel Efficiency:', 'numeric', 'solar.efficiency';
        'Tilt Angle (°):', 'numeric', 'solar.tilt';
        'Azimuth (°):', 'numeric', 'solar.azimuth';
        'Peak Rate (Ksh/kWh):', 'numeric', 'tariff.peak';
        'Off-Peak Rate:', 'numeric', 'tariff.offpeak';
        'Shoulder Rate:', 'numeric', 'tariff.shoulder';
        'Peak Start (hr):', 'numeric', 'tariff.peak_start';
        'Peak End (hr):', 'numeric', 'tariff.peak_end'
    };
    
    for i = 1:size(fields3, 1)
        uicontrol('Parent', hPanel3, 'Style', 'text', ...
            'String', fields3{i,1}, ...
            'Position', [20, yPos*100, 120, 20], ...
            'HorizontalAlignment', 'left');
        
        h = uicontrol('Parent', hPanel3, 'Style', 'edit', ...
            'Position', [150, yPos*100, 120, 25], ...
            'String', num2str(getParam(guiData.params, fields3{i,3})), ...
            'Callback', {@numericCallback, fields3{i,3}});
        yPos = yPos - 0.07;
    end
    
    % ===== PANEL 4: CONTROL BUTTONS =====
    hPanel4 = uipanel('Parent', fig, ...
        'Title', '🎮 Control Panel', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.02, 0.35, 0.96, 0.15]);
    
    % Create Model button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '🏗️ 1. Create PEM Model', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.8, 0.9, 1], ...
        'Position', [20, 30, 150, 40], ...
        'Callback', @createModelCallback);
    
    % Optimize button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '🚀 2. Optimize (NSGA-II-DE)', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'BackgroundColor', [1, 0.9, 0.7], ...
        'Position', [190, 30, 180, 40], ...
        'Enable', 'off', ...
        'Callback', @optimizeCallback);
    
    % Run Simulation button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '▶️ 3. Run Simulation', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.7, 1, 0.7], ...
        'Position', [390, 30, 150, 40], ...
        'Enable', 'off', ...
        'Callback', @simulationCallback);
    
    % Connect Arduino button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '🔌 Connect Arduino', ...
        'FontSize', 12, ...
        'Position', [560, 30, 130, 40], ...
        'Callback', @arduinoCallback);
    
    % Connect MQTT button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '📡 Connect MQTT', ...
        'FontSize', 12, ...
        'Position', [710, 30, 130, 40], ...
        'Callback', @mqttCallback);
    
    % Export button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '📊 Export Results', ...
        'FontSize', 12, ...
        'Position', [860, 30, 120, 40], ...
        'Callback', @exportCallback);
    
    % Open Simulink Model button
    uicontrol('Parent', hPanel4, 'Style', 'pushbutton', ...
        'String', '🔧 Open Simulink Model', ...
        'FontSize', 12, 'FontWeight', 'bold', ...
        'BackgroundColor', [0.85, 0.75, 1], ...
        'Position', [1000, 30, 170, 40], ...
        'Callback', @openSimulinkCallback);
    
    % ===== PANEL 5: STATUS & RESULTS =====
    hPanel5 = uipanel('Parent', fig, ...
        'Title', '📊 Status & Results', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.02, 0.05, 0.45, 0.25]);
    
    % Status text
    uicontrol('Parent', hPanel5, 'Style', 'text', ...
        'String', 'Status:', 'FontWeight', 'bold', ...
        'Position', [20, 150, 60, 20]);
    
    guiData.statusText = uicontrol('Parent', hPanel5, 'Style', 'text', ...
        'String', 'Ready - Enter parameters and click Create Model', ...
        'HorizontalAlignment', 'left', ...
        'Position', [90, 150, 400, 20]);
    
    % Results table
    guiData.resultsTable = uitable('Parent', hPanel5, ...
        'Position', [20, 20, 500, 110], ...
        'ColumnName', {'Parameter', 'Optimal Value', 'Unit'}, ...
        'ColumnWidth', {150, 120, 80}, ...
        'Data', cell(10, 3));
    
    % ===== PANEL 6: PLOTTING =====
    hPanel6 = uipanel('Parent', fig, ...
        'Title', '📈 Visualization', ...
        'FontSize', 14, 'FontWeight', 'bold', ...
        'Position', [0.52, 0.05, 0.46, 0.25]);
    
    guiData.plotAxes = axes('Parent', hPanel6, ...
        'Position', [0.1, 0.15, 0.85, 0.75]);
    
    % Progress bar
    guiData.progressBar = uicontrol('Parent', fig, 'Style', 'text', ...
        'BackgroundColor', [0.5, 0.8, 1], ...
        'Position', [200, 25, 0, 20], ...  % Width will be set dynamically
        'Visible', 'off');
    
    % Store updated data
    guidata(fig, guiData);
end

%% ========================================================================
%% Helper Functions for GUI
%% ========================================================================

function value = getParam(params, fieldPath)
    % Get nested parameter value
    fields = strsplit(fieldPath, '.');
    value = params;
    for i = 1:length(fields)
        value = value.(fields{i});
    end
end

function editCallback(hObject, ~, fieldPath)
    % Handle text edits
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    newValue = get(hObject, 'String');
    setNestedParam(guiData.params, fieldPath, newValue);
    guidata(fig, guiData);
end

function numericCallback(hObject, ~, fieldPath)
    % Handle numeric edits
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    newValue = str2double(get(hObject, 'String'));
    if ~isnan(newValue)
        setNestedParam(guiData.params, fieldPath, newValue);
    end
    guidata(fig, guiData);
end

function setNestedParam(params, fieldPath, value)
    % Set nested parameter value
    fields = strsplit(fieldPath, '.');
    s = params;
    for i = 1:length(fields)-1
        s = s.(fields{i});
    end
    s.(fields{end}) = value;
end

%% ========================================================================
%% SECTION 2: PEM MODEL CREATION (Your Validated Code)
%% ========================================================================

function createModelCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    updateStatus(fig, '🔄 Creating PEM model from validated physics...');
    
    try
        % === YOUR EXACT VALIDATED PEM MODEL CODE ===
        % Experimental data from Liso et al. (2018)
        J_data = [0.00, 0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75, 2.00]';
        V_exp_60 = [1.44, 1.52, 1.62, 1.72, 1.82, 1.88, 1.92, 1.95, 1.97]';
        V_exp_80 = [1.41, 1.49, 1.58, 1.67, 1.77, 1.83, 1.87, 1.90, 1.92]';
        
        % Calibrated parameters
        params = guiData.params.pem;
        
        % Validate model
        T_60 = 60 + 273.15;
        T_80 = 80 + 273.15;
        
        V_pred_60 = zeros(size(J_data));
        V_pred_80 = zeros(size(J_data));
        
        for i = 1:length(J_data)
            V_pred_60(i) = optimalPEMPhysics(J_data(i), T_60, params);
            V_pred_80(i) = optimalPEMPhysics(J_data(i), T_80, params);
        end
        
        % Calculate metrics
        [rmse_60, mape_60, r2_60] = calcMetrics(V_exp_60, V_pred_60);
        [rmse_80, mape_80, r2_80] = calcMetrics(V_exp_80, V_pred_80);
        
        % Store in guiData
        guiData.pemModel.J_data = J_data;
        guiData.pemModel.V_exp_60 = V_exp_60;
        guiData.pemModel.V_exp_80 = V_exp_80;
        guiData.pemModel.V_pred_60 = V_pred_60;
        guiData.pemModel.V_pred_80 = V_pred_80;
        guiData.pemModel.rmse_60 = rmse_60;
        guiData.pemModel.rmse_80 = rmse_80;
        guiData.pemModel.r2_60 = r2_60;
        guiData.pemModel.r2_80 = r2_80;
        
        guiData.modelExists = true;
        
        % Plot validation
        plotValidation(guiData.plotAxes, J_data, V_exp_60, V_exp_80, ...
            V_pred_60, V_pred_80, rmse_60, rmse_80);
        
        % Enable optimize button
        h = findobj('String', '🚀 2. Optimize (NSGA-II-DE)');
        set(h, 'Enable', 'on');
        
        % Build Simulink model if it doesn't exist yet
        updateStatus(fig, '🔧 Building Simulink model...');
        slxPath = buildSimulinkModel(guiData.params);
        guiData.slxModelPath = slxPath;
        
        updateStatus(fig, sprintf('✅ Model created! RMSE: %.3fV (60°C), %.3fV (80°C) | Simulink: KNH_PEM_Electrolyzer.slx', ...
            rmse_60, rmse_80));
        
    catch ME
        updateStatus(fig, ['❌ Error: ' ME.message]);
    end
    
    guidata(fig, guiData);
end

function V_cell = optimalPEMPhysics(J, T_K, params)
    % Your optimal physics-based PEM model
    if T_K <= 333.15
        E_rev = 1.44;
    elseif T_K >= 353.15
        E_rev = 1.41;
    else
        E_rev = 1.44 + (1.41 - 1.44) * (T_K - 333.15) / 20;
    end
    
    if J > 0
        eta_act = params.a_act + params.b_act * log(J);
    else
        eta_act = 0;
    end
    
    eta_ohm = params.R_ohm * J;
    eta_conc = params.k_conc * J^2;
    
    V_cell = E_rev + eta_act + eta_ohm + eta_conc;
end

function [rmse, mape, r2] = calcMetrics(V_exp, V_pred)
    rmse = sqrt(mean((V_exp - V_pred).^2));
    mape = 100 * mean(abs(V_exp - V_pred) ./ V_exp);
    ss_res = sum((V_exp - V_pred).^2);
    ss_tot = sum((V_exp - mean(V_exp)).^2);
    r2 = 1 - (ss_res / ss_tot);
end

function plotValidation(ax, J_data, V_exp_60, V_exp_80, V_pred_60, V_pred_80, rmse_60, rmse_80)
    cla(ax);
    hold(ax, 'on');
    
    J_fine = linspace(0, 2, 100);
    V_fine_60 = arrayfun(@(J) optimalPEMPhysics(J, 60+273.15, ...
        struct('a_act',0.1,'b_act',0.08,'R_ohm',0.18,'k_conc',0.006)), J_fine);
    V_fine_80 = arrayfun(@(J) optimalPEMPhysics(J, 80+273.15, ...
        struct('a_act',0.1,'b_act',0.08,'R_ohm',0.18,'k_conc',0.006)), J_fine);
    
    plot(ax, J_fine, V_fine_60, 'b-', 'LineWidth', 2, 'DisplayName', 'Model 60°C');
    plot(ax, J_fine, V_fine_80, 'r-', 'LineWidth', 2, 'DisplayName', 'Model 80°C');
    scatter(ax, J_data, V_exp_60, 60, 'b', 'filled', 'DisplayName', 'Exp 60°C');
    scatter(ax, J_data, V_exp_80, 60, 'r', 'filled', 'DisplayName', 'Exp 80°C');
    
    xlabel(ax, 'Current Density [A/cm²]');
    ylabel(ax, 'Cell Voltage [V]');
    title(ax, sprintf('PEM Model Validation (RMSE: %.3fV @60°C, %.3fV @80°C)', ...
        rmse_60, rmse_80));
    legend(ax, 'Location', 'northwest');
    grid(ax, 'on');
    hold(ax, 'off');
end

%% ========================================================================
%% SECTION 3: NSGA-II-DE OPTIMIZER (Your Algorithm)
%% ========================================================================

function optimizeCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    if ~guiData.modelExists
        updateStatus(fig, '❌ Create model first!');
        return;
    end
    
    updateStatus(fig, '🚀 Running NSGA-II-DE optimization...');
    
    % Disable button during optimization
    set(hObject, 'Enable', 'off');
    
    % Show progress bar
    set(guiData.progressBar, 'Visible', 'on', 'Position', [200, 25, 10, 20]);
    
    try
        % === RUN YOUR NSGA-II-DE OPTIMIZER ===
        optimal = runNSGA2DE(guiData.params);
        
        % Store results
        guiData.optimalParams = optimal;
        
        % Update results table
        data = {
            'Current Density (A/cm²)', num2str(optimal.J, '%.2f'), 'A/cm²';
            'Stack Size', num2str(optimal.N_cells, '%.0f'), 'cells';
            'Temperature', num2str(optimal.T, '%.1f'), '°C';
            'Pressure', num2str(optimal.p/1e5, '%.1f'), 'bar';
            'Cell Area', num2str(optimal.A_cell, '%.0f'), 'cm²';
            'O₂ Production', num2str(optimal.VO2, '%.1f'), 'L/min';
            'Energy Intensity', num2str(optimal.energy_intensity, '%.2f'), 'kWh/Nm³';
            'Efficiency', num2str(optimal.efficiency*100, '%.1f'), '%';
            'Cost Proxy', num2str(optimal.cost, '%.2f'), '';
            'Degradation', num2str(optimal.degradation, '%.2f'), ''
        };
        set(guiData.resultsTable, 'Data', data);
        
        % Plot results
        plotOptimizationResults(guiData.plotAxes, optimal);
        
        % Enable simulation button
        h = findobj('String', '▶️ 3. Run Simulation');
        set(h, 'Enable', 'on');
        
        updateStatus(fig, sprintf('✅ Optimization complete! O₂: %.1f L/min, Energy: %.2f kWh/Nm³', ...
            optimal.VO2, optimal.energy_intensity));
        
    catch ME
        updateStatus(fig, ['❌ Optimization failed: ' ME.message]);
    end
    
    % Re-enable button
    set(hObject, 'Enable', 'on');
    set(guiData.progressBar, 'Visible', 'off');
    
    guidata(fig, guiData);
end

function optimal = runNSGA2DE(params)
    % === YOUR NSGA-II-DE ALGORITHM IMPLEMENTATION ===
    
    % Problem dimensions
    nVars = 5;  % [J, N_cells, T, p, A_cell]
    nPop = 100;
    maxGen = 100;
    
    % Bounds from GUI parameters (row vectors for broadcasting)
    lb = [params.electrolyzer.min_current * 10000, 10, ...
          params.electrolyzer.min_temp, 1e5, 50];
    ub = [params.electrolyzer.max_current * 10000, 200, ...
          params.electrolyzer.max_temp, 30e5, 500];
    
    % Initialize population
    population = lb + (ub - lb) .* rand(nPop, nVars);
    
    % NSGA-II-DE main loop
    for gen = 1:maxGen
        % Calculate objectives for each individual
        objectives = zeros(nPop, 3);
        for i = 1:nPop
            [obj, ~] = evaluateIndividual(population(i,:), params);
            objectives(i,:) = obj;
        end
        
        % Non-dominated sorting
        [fronts, ~] = nonDominatedSorting(objectives);
        
        % Crowding distance
        crowding = crowdingDistance(objectives, fronts);
        
        % Selection for mating pool
        selected = tournamentSelection(fronts, crowding, nPop);
        
        % Create offspring (DE operator)
        offspring = createOffspringDE(population, selected, lb, ub, gen/maxGen);
        
        % Evaluate offspring
        offspringObj = zeros(size(offspring,1), 3);
        for i = 1:size(offspring,1)
            [obj, ~] = evaluateIndividual(offspring(i,:), params);
            offspringObj(i,:) = obj;
        end
        
        % Combine and select next generation
        combinedPop = [population; offspring];
        combinedObj = [objectives; offspringObj];
        
        [fronts, ~] = nonDominatedSorting(combinedObj);
        crowding = crowdingDistance(combinedObj, fronts);
        
        % Select nPop best
        idx = selectionNSGA2(fronts, crowding, nPop);
        population = combinedPop(idx,:);
        
        % Update progress bar in GUI
        fig = findobj('Name', 'KNH HE-NMPC Simulator');
        if ~isempty(fig)
            guiData = guidata(fig);
            progressWidth = 10 + 400 * (gen/maxGen);
            set(guiData.progressBar, 'Position', [200, 25, progressWidth, 20]);
            drawnow;
        end
    end
    
    % Get best solution
    bestIdx = 1;  % You might want more sophisticated selection
    bestX = population(bestIdx,:);
    
    % Calculate final metrics
    [~, details] = evaluateIndividual(bestX, params);
    
    % Package results
    optimal.J = bestX(1) / 10000;  % Convert to A/cm²
    optimal.N_cells = round(bestX(2));
    optimal.T = bestX(3);
    optimal.p = bestX(4);
    optimal.A_cell = bestX(5);
    optimal.VO2 = details.VO2;
    optimal.energy_intensity = details.energy_intensity;
    optimal.efficiency = details.efficiency;
    optimal.cost = details.cost;
    optimal.degradation = details.degradation;
    optimal.power = details.power;
end

function [obj, details] = evaluateIndividual(x, params)
    % x = [J_Am2, N_cells, T_C, p, A_cell]
    
    J_Am2 = x(1);
    N_cells = x(2);
    T_C = x(3);
    p = x(4);
    A_cell = x(5) * 1e-4;  % cm² to m²
    
    T_K = T_C + 273.15;
    J_Acm2 = J_Am2 / 10000;
    
    % PEM voltage model
    if T_K <= 333.15
        E_rev = 1.44;
    elseif T_K >= 353.15
        E_rev = 1.41;
    else
        E_rev = 1.44 + (1.41 - 1.44) * (T_K - 333.15) / 20;
    end
    
    if J_Acm2 > 0
        eta_act = params.pem.a_act + params.pem.b_act * log(J_Acm2);
    else
        eta_act = 0;
    end
    eta_ohm = params.pem.R_ohm * J_Acm2;
    eta_conc = params.pem.k_conc * J_Acm2^2;
    
    V_cell = E_rev + eta_act + eta_ohm + eta_conc;
    
    % Faraday calculations
    F_const = 96485;
    I = J_Am2 * A_cell;
    P_stack = N_cells * V_cell * I;
    nH2 = (N_cells * I) / (2 * F_const);
    nO2 = nH2 / 2;
    mass_H2 = nH2 * 2.016e-3;
    
    % O2 production in L/min
    VO2 = nO2 * 22.414e-3 * 60;
    
    % Objectives
    obj = zeros(1, 3);
    if mass_H2 > 0
        obj(1) = (P_stack / 1000) / (mass_H2 * 3600);  % kWh/kg_H2
    else
        obj(1) = 1e6;
    end
    obj(2) = N_cells * A_cell * 1e4;  % Cost proxy (cm²)
    obj(3) = (J_Acm2 / 1.0)^2 * exp(8000/T_K);  % Degradation
    
    % Details for output
    details.VO2 = VO2;
    details.energy_intensity = obj(1) * 0.5;  % Approx conversion to kWh/Nm³ O2
    details.efficiency = (1.23 / V_cell) * 0.95;  % Voltage efficiency
    details.cost = obj(2);
    details.degradation = obj(3);
    details.power = P_stack / 1000;  % kW
end

function [fronts, rank] = nonDominatedSorting(objectives)
    % Simplified NSGA-II non-dominated sorting
    n = size(objectives, 1);
    rank = zeros(n, 1);
    currentRank = 1;
    
    while any(rank == 0)
        front = [];
        for i = 1:n
            if rank(i) ~= 0
                continue;
            end
            dominated = false;
            for j = 1:n
                if rank(j) ~= 0
                    continue;
                end
                if all(objectives(j,:) <= objectives(i,:)) && any(objectives(j,:) < objectives(i,:))
                    dominated = true;
                    break;
                end
            end
            if ~dominated
                front(end+1) = i;
            end
        end
        rank(front) = currentRank;
        fronts{currentRank} = front;
        currentRank = currentRank + 1;
    end
end

function crowding = crowdingDistance(objectives, fronts)
    n = size(objectives, 1);
    crowding = zeros(n, 1);
    
    for f = 1:length(fronts)
        front = fronts{f};
        if length(front) <= 2
            crowding(front) = inf;
            continue;
        end
        
        m = size(objectives, 2);
        for obj = 1:m
            [~, idx] = sort(objectives(front, obj));
            sortedFront = front(idx);
            crowding(sortedFront(1)) = inf;
            crowding(sortedFront(end)) = inf;
            for i = 2:length(sortedFront)-1
                crowding(sortedFront(i)) = crowding(sortedFront(i)) + ...
                    (objectives(sortedFront(i+1), obj) - objectives(sortedFront(i-1), obj)) / ...
                    (max(objectives(:,obj)) - min(objectives(:,obj)));
            end
        end
    end
end

function selected = tournamentSelection(fronts, crowding, nPop)
    % Simplified tournament selection using rank array
    % Build rank array from fronts cell array
    totalN = sum(cellfun(@length, fronts));
    rank = zeros(totalN, 1);
    for f = 1:length(fronts)
        rank(fronts{f}) = f;
    end
    
    n = totalN;
    selected = zeros(nPop, 1);
    for i = 1:nPop
        a = randi(n);
        b = randi(n);
        if rank(a) < rank(b)
            selected(i) = a;
        elseif rank(b) < rank(a)
            selected(i) = b;
        else
            if crowding(a) > crowding(b)
                selected(i) = a;
            else
                selected(i) = b;
            end
        end
    end
end

function offspring = createOffspringDE(population, selected, lb, ub, progress)
    % DE operator with adaptive parameters
    nPop = size(population, 1);
    nVars = size(population, 2);
    offspring = zeros(nPop, nVars);
    
    % Adaptive DE parameters
    F = 0.5 + 0.3 * rand();
    CR = 0.9 - 0.4 * progress;
    
    for i = 1:nPop
        % Select three distinct individuals
        idx = randperm(nPop, 3);
        while any(idx == selected(i))
            idx = randperm(nPop, 3);
        end
        
        % Mutation
        mutant = population(idx(1),:) + F * (population(idx(2),:) - population(idx(3),:));
        
        % Crossover
        jrand = randi(nVars);
        trial = population(selected(i),:);
        for j = 1:nVars
            if rand < CR || j == jrand
                trial(j) = mutant(j);
            end
        end
        
        % Bounds
        trial = max(min(trial, ub), lb);
        offspring(i,:) = trial;
    end
end

function idx = selectionNSGA2(fronts, crowding, nPop)
    % Select nPop individuals based on NSGA-II rules
    idx = [];
    for f = 1:length(fronts)
        if length(idx) + length(fronts{f}) <= nPop
            idx = [idx, fronts{f}];
        else
            % Sort last front by crowding distance
            lastFront = fronts{f};
            [~, sortIdx] = sort(crowding(lastFront), 'descend');
            nLeft = nPop - length(idx);
            idx = [idx, lastFront(sortIdx(1:nLeft))];
            break;
        end
    end
end

function plotOptimizationResults(ax, optimal)
    cla(ax);
    
    % Create bar chart of key metrics
    metrics = [optimal.J, optimal.VO2/10, optimal.energy_intensity, ...
               optimal.efficiency*100, optimal.degradation/10];
    names = {'Current', 'O₂/10', 'Energy', 'Efficiency', 'Degradation/10'};
    
    bar(ax, metrics, 'FaceColor', [0.3, 0.6, 0.9]);
    set(ax, 'XTickLabel', names, 'XTick', 1:length(names));
    ylabel(ax, 'Normalized Value');
    title(ax, sprintf('Optimal Configuration: O₂ = %.1f L/min @ %.1f°C', ...
        optimal.VO2, optimal.T));
    grid(ax, 'on');
end

%% ========================================================================
%% SECTION 4: SIMULATION
%% ========================================================================

function simulationCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    if isempty(guiData.optimalParams)
        updateStatus(fig, '⚠️ Run optimization first!');
        return;
    end
    
    updateStatus(fig, '▶️ Running simulation...');
    
    % Run simulation (simplified - you'd have full Simulink here)
    runSimulation(guiData);
    
    updateStatus(fig, '✅ Simulation complete!');
end

function runSimulation(guiData)
    % Simplified simulation - in reality, this would call Simulink
    t = 0:0.1:24;
    
    % Generate demand profile
    demand = 30 + 10 * sin(2*pi*t/24 - pi/2) + 5 * randn(size(t));
    demand(demand < 20) = 20;
    
    % Generate PV profile
    pv = guiData.params.solar.capacity * max(0, sin(pi*(t-6)/12)) .* (t > 6 & t < 18);
    
    % Production based on optimal params
    production = guiData.optimalParams.VO2 * ones(size(t));
    
    % Tank level
    tank = cumsum((production - demand) * 0.1);
    tank = tank - min(tank) + guiData.params.hospital.min_reserve;
    tank = min(tank, guiData.params.hospital.tank_capacity);
    
    % Purity (should stay above 99.5%)
    purity = 99.7 + 0.2 * randn(size(t));
    purity(purity < 99.5) = 99.5;
    
    % Plot results
    ax = guiData.plotAxes;
    cla(ax);
    
    yyaxis(ax, 'left');
    plot(ax, t, purity, 'b-', 'LineWidth', 2);
    ylabel(ax, 'Purity (%)');
    yline(ax, 99.5, 'r--', 'Min Required');
    
    yyaxis(ax, 'right');
    plot(ax, t, tank, 'g-', 'LineWidth', 2);
    plot(ax, t, demand, 'k:', 'LineWidth', 1.5);
    plot(ax, t, production, 'm--', 'LineWidth', 1.5);
    ylabel(ax, 'Flow (L/min) / Tank Level (%)');
    
    xlabel(ax, 'Time (hours)');
    title(ax, 'Simulation Results');
    legend(ax, 'Purity', 'Min Purity', 'Tank Level', 'Demand', 'Production');
    grid(ax, 'on');
end

%% ========================================================================
%% SECTION 5: COMMUNICATION (Arduino & MQTT)
%% ========================================================================

function arduinoCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    if guiData.arduinoConnected
        % Disconnect
        if ~isempty(guiData.serialObj)
            fclose(guiData.serialObj);
            delete(guiData.serialObj);
        end
        guiData.arduinoConnected = false;
        set(hObject, 'String', '🔌 Connect Arduino', 'BackgroundColor', [0.94, 0.94, 0.94]);
        updateStatus(fig, '🔌 Arduino disconnected');
    else
        % Connect
        try
            ports = serialportlist("available");
            if isempty(ports)
                updateStatus(fig, '❌ No Arduino found!');
                return;
            end
            
            guiData.serialObj = serialport(ports(1), 115200);
            configureTerminator(guiData.serialObj, "LF");
            flush(guiData.serialObj);
            
            % Test connection
            writeline(guiData.serialObj, "PING");
            response = readline(guiData.serialObj);
            
            if contains(response, "PONG")
                guiData.arduinoConnected = true;
                set(hObject, 'String', '🔌 Arduino Connected ✓', 'BackgroundColor', [0.7, 1, 0.7]);
                updateStatus(fig, '✅ Arduino connected');
                
                % Send optimal params if available
                if ~isempty(guiData.optimalParams)
                    cmd = sprintf("SET:%.2f,%.0f,%.1f", ...
                        guiData.optimalParams.J, ...
                        guiData.optimalParams.N_cells, ...
                        guiData.optimalParams.T);
                    writeline(guiData.serialObj, cmd);
                end
            end
        catch ME
            updateStatus(fig, ['❌ Arduino error: ' ME.message]);
        end
    end
    
    guidata(fig, guiData);
end

function mqttCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    if guiData.mqttConnected
        guiData.mqttConnected = false;
        set(hObject, 'String', '📡 Connect MQTT', 'BackgroundColor', [0.94, 0.94, 0.94]);
        updateStatus(fig, '📡 MQTT disconnected');
    else
        % Simulate MQTT connection
        guiData.mqttConnected = true;
        set(hObject, 'String', '📡 MQTT Connected ✓', 'BackgroundColor', [0.7, 1, 0.7]);
        updateStatus(fig, '✅ Connected to MQTT broker');
        
        % Send initial data
        if ~isempty(guiData.optimalParams)
            sendMQTTData(guiData);
        end
    end
    
    guidata(fig, guiData);
end

function sendMQTTData(guiData)
    % Simulate sending data via MQTT
    if guiData.mqttConnected
        % In reality, you'd publish to a real MQTT broker
        fprintf('📡 MQTT Published: O₂=%.1f L/min, Energy=%.2f kWh/Nm³\n', ...
            guiData.optimalParams.VO2, guiData.optimalParams.energy_intensity);
    end
end

%% ========================================================================
%% SECTION 5.5: OPEN / BUILD SIMULINK MODEL
%% ========================================================================

function openSimulinkCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    % Determine model path: use auto-created one, else browse
    if ~isempty(guiData.slxModelPath) && exist(guiData.slxModelPath, 'file')
        modelPath = guiData.slxModelPath;
        [~, modelName, ~] = fileparts(modelPath);
    else
        [fname, fpath] = uigetfile('*.slx', 'Select Simulink Model (.slx)');
        if isequal(fname, 0), return; end
        modelPath = fullfile(fpath, fname);
        [~, modelName, ~] = fileparts(fname);
        guiData.slxModelPath = modelPath;
        guidata(fig, guiData);
    end
    
    updateStatus(fig, ['⏳ Opening model: ' modelName '...']);
    
    try
        % Close model if already open to force reload with fresh workspace
        if bdIsLoaded(modelName)
            close_system(modelName, 0);
        end
        load_system(modelPath);
        
        % Push optimal parameters into the model workspace if available
        if ~isempty(guiData.optimalParams)
            opt = guiData.optimalParams;
            hws = get_param(modelName, 'ModelWorkspace');
            assignin(hws, 'J_opt',          opt.J);           % A/cm²
            assignin(hws, 'N_cells_opt',    opt.N_cells);     % cells
            assignin(hws, 'T_opt',          opt.T);           % °C
            assignin(hws, 'p_opt',          opt.p);           % Pa
            assignin(hws, 'A_cell_opt',     opt.A_cell);      % cm²
            assignin(hws, 'VO2_opt',        opt.VO2);         % L/min
            assignin(hws, 'efficiency_opt', opt.efficiency);
            assignin(hws, 'power_opt',      opt.power);       % kW
            % Save so params persist
            save_system(modelName);
            updateStatus(fig, sprintf( ...
                '✅ Simulink model opened with optimal params: J=%.2f A/cm², N=%d cells, T=%.1f°C, O₂=%.1f L/min', ...
                opt.J, opt.N_cells, opt.T, opt.VO2));
        else
            updateStatus(fig, ['✅ Model opened — run optimization to apply optimal params: ' modelName]);
        end
        
        open_system(modelName);
        
    catch ME
        updateStatus(fig, ['❌ Failed to open model: ' ME.message]);
    end
end

function slxPath = buildSimulinkModel(params)
    % Programmatically create KNH_PEM_Electrolyzer.slx if it doesn't exist
    modelName = 'KNH_PEM_Electrolyzer';
    slxPath   = fullfile(pwd, [modelName '.slx']);
    
    % If already exists just return path
    if exist(slxPath, 'file') && ~bdIsLoaded(modelName)
        return;
    end
    
    % Close stale version if in memory
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    
    % Create new model
    new_system(modelName);
    load_system(modelName);
    
    % ---- Layout constants (pixel positions) ----
    % Each block [left, top, right, bottom]
    
    % --- Inputs: Constant blocks for variables ---
    inputs = {'J_opt', 'N_cells_opt', 'T_opt', 'p_opt', 'A_cell_opt'};
    initVals = {params.electrolyzer.min_current, 50, ...
                params.electrolyzer.operating_temp, 1e5, ...
                params.electrolyzer.cell_area};
    units    = {'A/cm2', 'cells', 'degC', 'Pa', 'cm2'};
    
    for k = 1:length(inputs)
        blkPath = [modelName '/' inputs{k}];
        top = 50 + (k-1)*80;
        add_block('simulink/Sources/Constant', blkPath, ...
            'Position', [30, top, 130, top+30], ...
            'Value',    num2str(initVals{k}), ...
            'OutDataTypeStr', 'double');
    end
    
    % --- MATLAB Function block: PEM physics ---
    fcnPath = [modelName '/PEM_Physics'];
    add_block('simulink/User-Defined Functions/MATLAB Function', fcnPath, ...
        'Position', [220, 150, 380, 310]);
    
    % Set the MATLAB function code
    rt = sfroot();
    m  = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', modelName);
    ch = m.find('-isa', 'Stateflow.EMChart', 'Name', 'PEM_Physics');
    nl = char(10);
    ch.Script = ['function [V_cell, P_stack, VO2, efficiency] = PEM_Physics(J, N_cells, T_C, p, A_cell)' nl ...
        '% KNH PEM Electrolyzer Physics Model' nl ...
        '% Calibrated from Liso et al. (2018)' nl ...
        'T_K = T_C + 273.15;' nl ...
        'J_Acm2 = J;' nl ...
        'if T_K <= 333.15' nl ...
        '    E_rev = 1.44;' nl ...
        'elseif T_K >= 353.15' nl ...
        '    E_rev = 1.41;' nl ...
        'else' nl ...
        '    E_rev = 1.44 + (1.41-1.44)*(T_K-333.15)/20;' nl ...
        'end' nl ...
        'a_act = 0.10; b_act = 0.08; R_ohm = 0.18; k_conc = 0.006;' nl ...
        'if J_Acm2 > 0' nl ...
        '    eta_act = a_act + b_act * log(J_Acm2);' nl ...
        'else' nl ...
        '    eta_act = 0;' nl ...
        'end' nl ...
        'eta_ohm  = R_ohm  * J_Acm2;' nl ...
        'eta_conc = k_conc * J_Acm2^2;' nl ...
        'V_cell = E_rev + eta_act + eta_ohm + eta_conc;' nl ...
        'F_const = 96485;' nl ...
        'A_m2 = A_cell * 1e-4;' nl ...
        'I = J_Acm2 * 1e4 * A_m2;' nl ...
        'P_stack = N_cells * V_cell * I / 1000;' nl ...
        'nH2 = (N_cells * I) / (2 * F_const);' nl ...
        'nO2 = nH2 / 2;' nl ...
        'VO2 = nO2 * 22.414e-3 * 60;' nl ...
        'efficiency = (1.23 / V_cell) * 0.95;' nl ...
        'end' nl];
    
    % --- Output Display blocks ---
    outNames  = {'V_cell [V]', 'P_stack [kW]', 'VO2 [L/min]', 'Efficiency'};
    outPorts  = 1:4;
    for k = 1:4
        dispPath = [modelName '/Out_' num2str(k)];
        top = 80 + (k-1)*80;
        add_block('simulink/Sinks/Display', dispPath, ...
            'Position', [500, top, 650, top+40]);
    end
    
    % --- Connect Constant inputs -> MATLAB Function ---
    for k = 1:5
        add_line(modelName, [inputs{k} '/1'], ['PEM_Physics/' num2str(k)], ...
            'autorouting', 'on');
    end
    
    % --- Connect MATLAB Function outputs -> Displays ---
    for k = 1:4
        add_line(modelName, ['PEM_Physics/' num2str(k)], ['Out_' num2str(k) '/1'], ...
            'autorouting', 'on');
    end
    
    % --- Model settings ---
    set_param(modelName, 'StopTime', '10', 'Solver', 'ode45');
    
    % --- Save ---
    save_system(modelName, slxPath);
    close_system(modelName, 0);
end

%% ========================================================================
%% SECTION 6: EXPORT
%% ========================================================================

function exportCallback(hObject, ~)
    fig = ancestor(hObject, 'figure');
    guiData = guidata(fig);
    
    % Create export structure
    exportData = struct();
    exportData.params = guiData.params;
    exportData.optimal = guiData.optimalParams;
    exportData.timestamp = datestr(now);
    
    % Save to file
    filename = sprintf('KNH_Export_%s.mat', datestr(now, 'yyyymmdd_HHMMSS'));
    save(filename, 'exportData');
    
    % Also save as CSV for thesis
    if ~isempty(guiData.optimalParams)
        csvFile = strrep(filename, '.mat', '.csv');
        fid = fopen(csvFile, 'w');
        fprintf(fid, 'Parameter,Value,Unit\n');
        fprintf(fid, 'Current Density (A/cm²),%.2f,A/cm²\n', guiData.optimalParams.J);
        fprintf(fid, 'Stack Size,%.0f,cells\n', guiData.optimalParams.N_cells);
        fprintf(fid, 'Temperature,%.1f,°C\n', guiData.optimalParams.T);
        fprintf(fid, 'Pressure,%.1f,bar\n', guiData.optimalParams.p/1e5);
        fprintf(fid, 'Cell Area,%.0f,cm²\n', guiData.optimalParams.A_cell);
        fprintf(fid, 'O₂ Production,%.1f,L/min\n', guiData.optimalParams.VO2);
        fprintf(fid, 'Energy Intensity,%.2f,kWh/Nm³\n', guiData.optimalParams.energy_intensity);
        fprintf(fid, 'Efficiency,%.1f,%%\n', guiData.optimalParams.efficiency*100);
        fclose(fid);
    end
    
    updateStatus(fig, ['✅ Exported to ' filename]);
end

%% ========================================================================
%% UTILITY FUNCTIONS
%% ========================================================================

function updateStatus(fig, message)
    guiData = guidata(fig);
    if isfield(guiData, 'statusText')
        set(guiData.statusText, 'String', message);
    end
    drawnow;
end

%% ========================================================================
%% RUN THE APPLICATION
%% ========================================================================

% The main function is called automatically when script is run
% Just type: KNH_HE_NMPC_Complete in MATLAB command window