clc;
clear;
close all;

% INTERACTIVE INPUT

defaultCitizens = 100;
defaultInfluencers = 6;
defaultExperts = 3;
defaultTimeSteps = 80;

try
    prompt = {
        'Number of Citizens (50 - 200):', ...
        'Number of Influencers (3 - 10):', ...
        'Number of Education Experts (1 - 5):', ...
        'Time Steps (50 - 100):'
    };

    dlgTitle = 'ABM Opinion Dynamics Setup';
    dims = [1 50];

    defaultAns = {
        num2str(defaultCitizens), ...
        num2str(defaultInfluencers), ...
        num2str(defaultExperts), ...
        num2str(defaultTimeSteps)
    };

    answer = inputdlg(prompt, dlgTitle, dims, defaultAns);

    if isempty(answer)
        numCitizens = defaultCitizens;
        numInfluencers = defaultInfluencers;
        numExperts = defaultExperts;
        timeSteps = defaultTimeSteps;
    else
        numCitizens = str2double(answer{1});
        numInfluencers = str2double(answer{2});
        numExperts = str2double(answer{3});
        timeSteps = str2double(answer{4});
    end

catch
    disp('GUI dialog not available. Using Command Window input.');

    temp = input('Number of Citizens (50 - 200), default 100: ');
    if isempty(temp), numCitizens = defaultCitizens; else, numCitizens = temp; end

    temp = input('Number of Influencers (3 - 10), default 6: ');
    if isempty(temp), numInfluencers = defaultInfluencers; else, numInfluencers = temp; end

    temp = input('Number of Education Experts (1 - 5), default 3: ');
    if isempty(temp), numExperts = defaultExperts; else, numExperts = temp; end

    temp = input('Time Steps (50 - 100), default 80: ');
    if isempty(temp), timeSteps = defaultTimeSteps; else, timeSteps = temp; end

end

% Make sure inputs follow assignment range
numCitizens = max(50, min(200, round(numCitizens)));
numInfluencers = max(3, min(10, round(numInfluencers)));
numExperts = max(1, min(5, round(numExperts)));
timeSteps = max(50, min(100, round(timeSteps)));

% Randomness is not fixed.
% Every time the model runs, it creates a new random population,
% network, trust values, and noise. The scenario parameters still keep
% the graph pattern within the expected range.
try
    rng('shuffle');
catch
    shuffleSeed = sum(100 * clock);
    rand('seed', shuffleSeed);
    randn('seed', shuffleSeed);
end

% ============================================================
% 2. SCENARIO MENU
% ============================================================

scenarioNames = {
    'Baseline Model', ...
    'Strong Influencer Impact', ...
    'Strong Expert Intervention', ...
    'Low Trust Environment'
};

try
    selectedOption = menu('Choose Simulation Scenario', ...
        'Scenario 1: Baseline Model', ...
        'Scenario 2: Strong Influencer Impact', ...
        'Scenario 3: Strong Expert Intervention', ...
        'Scenario 4: Low Trust Environment', ...
        'Run All 4 Scenarios');
catch
    disp(' ');
    disp('Choose Simulation Scenario:');
    disp('1. Scenario 1: Baseline Model');
    disp('2. Scenario 2: Strong Influencer Impact');
    disp('3. Scenario 3: Strong Expert Intervention');
    disp('4. Scenario 4: Low Trust Environment');
    disp('5. Run All 4 Scenarios');

    selectedOption = input('Enter choice, default 5: ');
    if isempty(selectedOption), selectedOption = 5; end
end

if selectedOption < 1 || selectedOption > 5
    selectedOption = 5;
end

if selectedOption == 5
    scenariosToRun = 1:4;
else
    scenariosToRun = selectedOption;
end

numScenarios = length(scenariosToRun);

% ============================================================
% 3. BASE MODEL SETUP
% ============================================================

% Citizen opinion O_i in range [-1, +1]
% -1 = strongly against AI
%  0 = neutral
% +1 = strongly support AI
baseCitizenOpinion = -1 + 2 * rand(numCitizens, 1);

% Influencers have stronger/extreme opinions.
% Baseline uses mixed positive and negative influencers.
baseInfluencerOpinion = zeros(numInfluencers, 1);

for k = 1:numInfluencers
    if k <= ceil(numInfluencers / 2)
        baseInfluencerOpinion(k) = -(0.6 + 0.4 * rand);
    else
        baseInfluencerOpinion(k) = 0.6 + 0.4 * rand;
    end
end

% Shuffle influencer opinions
shuffleIndex = randperm(numInfluencers);
baseInfluencerOpinion = baseInfluencerOpinion(shuffleIndex);

% Education experts are balanced / mildly supportive
baseExpertOpinion = 0.40 + 0.15 * rand(numExperts, 1);

% Random social network among citizens
connectionProb = 0.15;
baseNetwork = rand(numCitizens, numCitizens) < connectionProb;

% Remove self-connections
for i = 1:numCitizens
    baseNetwork(i, i) = 0;
end

% Ensure every citizen has at least one neighbour
for i = 1:numCitizens
    if sum(baseNetwork(i, :)) == 0
        randomNeighbour = randi(numCitizens);
        while randomNeighbour == i
            randomNeighbour = randi(numCitizens);
        end
        baseNetwork(i, randomNeighbour) = 1;
    end
end

% Trust between citizens, trust in experts, trust in influencers
baseTrustCitizen = rand(numCitizens, numCitizens);
baseTrustExpert = 0.70 + 0.30 * rand(numCitizens, 1);
baseTrustInfluencer = 0.40 + 0.40 * rand(numCitizens, 1);

% Each citizen follows one main influencer
baseFollowedInfluencer = randi(numInfluencers, numCitizens, 1);

% ============================================================
% 4. STORAGE FOR RESULTS
% ============================================================

avgOpinionAll = zeros(4, timeSteps);
varianceAll = zeros(4, timeSteps);
finalOpinionsAll = zeros(4, numCitizens);
opinionHistoryAll = zeros(4, numCitizens, timeSteps);

supportPercentAll = zeros(4, 1);
neutralPercentAll = zeros(4, 1);
againstPercentAll = zeros(4, 1);
interpretationAll = cell(4, 1);

% ============================================================
% 5. SIMULATION LOOP
% ============================================================

for scenarioIndex = 1:numScenarios

    scenario = scenariosToRun(scenarioIndex);

    citizenOpinion = baseCitizenOpinion;
    influencerOpinion = baseInfluencerOpinion;
    expertOpinion = baseExpertOpinion;
    network = baseNetwork;
    trustCitizen = baseTrustCitizen;
    trustExpert = baseTrustExpert;
    trustInfluencer = baseTrustInfluencer;
    followedInfluencer = baseFollowedInfluencer;

    % Default parameters
    alpha = 0.08;
    beta  = 0.12;
    gamma = 0.12;
    delta = 0.06;
    sigma = 0.015;
    eta   = 0.35;

    % Scenario settings
    if scenario == 1

        % Scenario 1: Baseline Model
        alpha = 0.08;
        beta  = 0.12;
        gamma = 0.12;
        delta = 0.06;
        sigma = 0.015;
        eta   = 0.35;

    elseif scenario == 2

        % Scenario 2: Strong Influencer Impact
        citizenOpinion = 0.70 + 0.12 * randn(numCitizens, 1);
        citizenOpinion = max(-1, min(1, citizenOpinion));

        alpha = 0.04;
        beta  = 0.06;
        gamma = 0.05;
        delta = 0.35;
        sigma = 0.012;
        eta   = 0.45;

        trustInfluencer = 0.80 + 0.20 * rand(numCitizens, 1);

        elseif scenario == 3

        % Scenario 3: Strong Expert Intervention
        alpha = 0.10;
        beta  = 0.15;
        gamma = 0.75;
        delta = 0.05;
        sigma = 0.01;

        trustExpert = 0.85 + 0.15 * rand(numCitizens, 1);
        expertOpinion = 0.45 + 0.10 * rand(numExperts, 1);

    elseif scenario == 4

        % Scenario 4: Low Trust Environment
        citizenOpinion = -0.03 + 0.35 * randn(numCitizens, 1);
        citizenOpinion = max(-1, min(1, citizenOpinion));

        alpha = 0.03;
        beta  = 0.04;
        gamma = 0.04;
        delta = 0.03;
        sigma = 0.020;
        eta   = 0.18;

        trustCitizen = 0.20 * trustCitizen;
        trustExpert = 0.25 * trustExpert;
        trustInfluencer = 0.25 * trustInfluencer;

    end

    opinionHistory = zeros(numCitizens, timeSteps);

    for t = 1:timeSteps

        newOpinion = citizenOpinion;

        if scenario == 2
            campaignOpinion = 0.52 + 0.24 * exp(-(t - 1) / 18);
            influencerOpinion = campaignOpinion + 0.03 * randn(numInfluencers, 1);
            influencerOpinion = max(-1, min(1, influencerOpinion));
        end

        for i = 1:numCitizens

            neighbours = find(network(i, :) == 1);

            % 1. Direct influence from one connected citizen
            % D_i = alpha * T_ij * (O_j - O_i)
            if length(neighbours) > 0

                selectedNeighbour = neighbours(randi(length(neighbours)));

                directEffect = alpha * trustCitizen(i, selectedNeighbour) * ...
                    (citizenOpinion(selectedNeighbour) - citizenOpinion(i));

                % 2. Averaging effect from neighbours
                % A_i = beta * avg(T_i) * (avg(O_neighbour) - O_i)
                neighbourAverage = mean(citizenOpinion(neighbours));
                averageTrust = mean(trustCitizen(i, neighbours));

                averagingEffect = beta * averageTrust * ...
                    (neighbourAverage - citizenOpinion(i));

            else
                directEffect = 0;
                averagingEffect = 0;
            end

            % 3. Education expert effect
            % E_i = gamma * T_expert * (avg(O_expert) - O_i)
            avgExpertOpinion = mean(expertOpinion);

            expertEffect = gamma * trustExpert(i) * ...
                (avgExpertOpinion - citizenOpinion(i));

            % 4. Influencer effect
            % F_i = delta * T_influencer * (O_influencer - O_i)
            selectedInfluencer = followedInfluencer(i);

            influencerEffect = delta * trustInfluencer(i) * ...
                (influencerOpinion(selectedInfluencer) - citizenOpinion(i));

            % 5. Random noise / misinformation
            % M_i = sigma * randomNoise
            misinformationEffect = sigma * randn;

            % Final opinion update equation
            % O_i(t+1) = clip[O_i(t) + eta(D + A + E + F) + M]
            newOpinion(i) = citizenOpinion(i) ...
                + eta * (directEffect + averagingEffect + expertEffect + influencerEffect) ...
                + misinformationEffect;

            % [-1, +1]
            newOpinion(i) = max(-1, min(1, newOpinion(i)));

        end

        citizenOpinion = newOpinion;

        opinionHistory(:, t) = citizenOpinion;
        avgOpinionAll(scenario, t) = mean(citizenOpinion);
        varianceAll(scenario, t) = var(citizenOpinion);

    end

    finalOpinionsAll(scenario, :) = citizenOpinion';
    opinionHistoryAll(scenario, :, :) = opinionHistory;

    % Final classification
    finalOpinions = finalOpinionsAll(scenario, :);

    supportPercent = sum(finalOpinions > 0.3) / numCitizens * 100;
    againstPercent = sum(finalOpinions < -0.3) / numCitizens * 100;
    neutralPercent = sum(finalOpinions >= -0.3 & finalOpinions <= 0.3) / numCitizens * 100;

    supportPercentAll(scenario) = supportPercent;
    neutralPercentAll(scenario) = neutralPercent;
    againstPercentAll(scenario) = againstPercent;

    avgFinal = mean(finalOpinions);
    varFinal = var(finalOpinions);

    if supportPercent > 70 && varFinal < 0.05
        interpretation = 'Consensus Support';
    elseif againstPercent > 70 && varFinal < 0.05
        interpretation = 'Consensus Against';
    elseif varFinal >= 0.15 && supportPercent > 20 && againstPercent > 20
        interpretation = 'Fragmentation / Polarization';
    elseif neutralPercent > 60 && varFinal < 0.10
        interpretation = 'Moderate Consensus';
    else
        interpretation = 'Mixed / Fragmented';
    end

    interpretationAll{scenario} = interpretation;

end

% 6. FINAL RESULT TABLE

fprintf('\nFINAL SIMULATION RESULTS - New random run\n');
fprintf('--------------------------------------------------------------------------------------------------------------\n');
fprintf('%-30s %-12s %-12s %-12s %-12s %-12s %-25s\n', ...
    'Scenario', 'Avg', 'Variance', 'Support %', 'Neutral %', 'Against %', 'Interpretation');
fprintf('--------------------------------------------------------------------------------------------------------------\n');

for scenarioIndex = 1:numScenarios

    scenario = scenariosToRun(scenarioIndex);
    finalOpinions = finalOpinionsAll(scenario, :);

    avgFinal = mean(finalOpinions);
    varFinal = var(finalOpinions);

    fprintf('%-30s %-12.4f %-12.4f %-12.2f %-12.2f %-12.2f %-25s\n', ...
        scenarioNames{scenario}, ...
        avgFinal, ...
        varFinal, ...
        supportPercentAll(scenario), ...
        neutralPercentAll(scenario), ...
        againstPercentAll(scenario), ...
        interpretationAll{scenario});

end

fprintf('--------------------------------------------------------------------------------------------------------------\n');
% 7. GRAPH PRESENTATION

for scenario = 1:4

    figure('Name', ['Figure ', num2str(scenario), ': ', scenarioNames{scenario}]);

    subplot(2,2,1);
    plot(1:timeSteps, avgOpinionAll(scenario, :), 'LineWidth', 2);
    xlabel('Time Step');
    ylabel('Opinion');
    title('Average Opinion');
    grid on;

    subplot(2,2,2);
    hist(finalOpinionsAll(scenario, :), 15);
    xlabel('Opinion');
    ylabel('Frequency');
    title('Final Opinion Distribution');
    xlim([-1 1]);
    grid on;

    subplot(2,2,[3 4]);

    selectedHistory = squeeze(opinionHistoryAll(scenario, :, :));
    [T, A] = meshgrid(1:timeSteps, 1:numCitizens);

    surf(T, A, selectedHistory);
    shading interp;

    xlabel('Time Step');
    ylabel('Agent');
    zlabel('Opinion');
    title('3D Opinion Evolution');
    zlim([-1 1]);
    grid on;
    view(-135, 30);

end

xlabel('X Position');
ylabel('Y Position');
title('Random Citizen Social Network');
grid on;
