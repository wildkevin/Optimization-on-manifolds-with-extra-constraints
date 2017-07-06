function [stats, finalX] = bfgsnonsmoothCleanCompare(problem, x, options)
    
    timetic = tic();
    M = problem.M;

    if ~exist('x','var')
        xCur = M.rand();
    else 
        xCur = x;
    end
    
    localdefaults.minstepsize = 1e-50;
    localdefaults.maxiter = 10000;
    localdefaults.tolgradnorm = 1e-12;
    localdefaults.memory = 15;
    localdefaults.c1 = 0.0; 
    localdefaults.c2 = 0.5;
    localdefaults.discrepency = 1e-6;
    
    % Merge global and local defaults, then merge w/ user options, if any.
    localdefaults = mergeOptions(getGlobalDefaults(), localdefaults);
    if ~exist('options', 'var') || isempty(options)
        options = struct();
    end
    options = mergeOptions(localdefaults, options);
   
%     xCurGradient = getGradient(problem, xCur);
    xCurGradient = problem.gradAlt(xCur, options.discrepency);
    xCurGradNorm = M.norm(xCur, xCurGradient);
    xCurCost = getCost(problem, xCur);
    
    k = 0;
    iter = 0;
    sHistory = cell(1, options.memory);
    yHistory = cell(1, options.memory);
    rhoHistory = cell(1, options.memory);
    alpha = 1;
    scaleFactor = 1;
    stepsize = 1;
    existsAssumedoptX = exist('options','var') && ~isempty(options) && exist('options.assumedoptX', 'var');
    lsiters = 1;
    ultimatum = 0;
    
    stats.gradnorms = zeros(1,options.maxiter);
    stats.alphas = zeros(1,options.maxiter);
    stats.stepsizes = zeros(1,options.maxiter);
    stats.costs = zeros(1,options.maxiter);
    stats.xHistory = cell(1,options.maxiter);
    if existsAssumedoptX
        stats.distToAssumedOptX = zeros(1,options.maxiter);
    end
    
    savestats();

    fprintf(' iter\t               cost val\t    grad. norm\t   lsiters\n');

    
%     if M.norm(xNext, problem.gradAlt(xNext, options.discrepency*10)) < 1e-6
%         options.discrepency = options.discrepency/10;
%         fprintf('Descrease Discrepency up to %.16e\n', options.discrepency);
%         k=0;
%         scaleFactor = 1;
%         continue;
%     end
    
    while (1)
        %_______Print Information and stop information________
        fprintf('%5d\t%+.16e\t%.8e\t %d\n', iter, xCurCost, xCurGradNorm, lsiters);

        if (xCurGradNorm < options.tolgradnorm)
            fprintf('Target Reached\n');
            break;
        end
        if (stepsize <= options.minstepsize)
            fprintf('Stepsize too small\n')
            break;
        end
        if (iter > options.maxiter)
            fprintf('maxiter reached\n')
            break;
        end

        %_______Get Direction___________________________

        p = getDirection(M, xCur, xCurGradient, sHistory,...
            yHistory, rhoHistory, scaleFactor, min(k, options.memory));
        
%         p = -getGradient(problem, xCur);
        
        %_______Line Search____________________________
        dir_derivative = M.inner(xCur,xCurGradient,p);
        if  dir_derivative> 0
            fprintf('directionderivative IS POSITIVE\n');
        end

        [xNextCost, alpha, fail, lsiters] = linesearchnonsmooth(problem, M, xCur, p, xCurCost, dir_derivative, options.c1, options.c2);
        step = M.lincomb(xCur, alpha, p);
        stepsize = M.norm(xCur, step);
        xNext = M.retr(xCur, step, 1);
        if fail == 1 || stepsize < 1e-14
            if ultimatum == 1
                fprintf('Even descent direction does not help us now\n');
                break;
            else
                k = 0;
                scaleFactor = 1;
                ultimatum = 1;
                continue;
            end
        else
            ultimatum = 0;
        end
       
        
        %_______Updating the next iteration_______________
%         xNextGradient = getGradient(problem, xNext);
        xNextGradient = problem.gradAlt(xNext, options.discrepency);        
        
        sk = M.isotransp(xCur, xNext, step);
        yk = M.lincomb(xNext, 1, xNextGradient,...
            -1, M.isotransp(xCur, xNext, xCurGradient));

        inner_sk_yk = M.inner(xNext, yk, sk);
        arbconst = 0;
        if (inner_sk_yk /M.inner(xNext, sk, sk))> arbconst * xCurGradNorm
            rhok = 1/inner_sk_yk;
            scaleFactor = inner_sk_yk / M.inner(xNext, yk, yk);
            if (k>= options.memory)
                for  i = 2:options.memory
                    sHistory{i} = M.isotransp(xCur, xNext, sHistory{i});
                    yHistory{i} = M.isotransp(xCur, xNext, yHistory{i});
                end
                sHistory = sHistory([2:end 1]);
                sHistory{options.memory} = sk;
                yHistory = yHistory([2:end 1]);
                yHistory{options.memory} = yk;
                rhoHistory = rhoHistory([2:end 1]);
                rhoHistory{options.memory} = rhok;
            else
                for  i = 1:k
                    sHistory{i} = M.isotransp(xCur, xNext, sHistory{i});
                    yHistory{i} = M.isotransp(xCur, xNext, yHistory{i});
                end
                sHistory{k+1} = sk;
                yHistory{k+1} = yk;
                rhoHistory{k+1} = rhok;
            end
            k = k+1;
        else
            for  i = 1:min(k,options.memory)
                sHistory{i} = M.isotransp(xCur, xNext, sHistory{i});
                yHistory{i} = M.isotransp(xCur, xNext, yHistory{i});
            end
        end

        iter = iter + 1;
        xCur = xNext;
        xCurGradient = xNextGradient;
        xCurGradNorm = M.norm(xCur, xNextGradient);
        xCurCost = xNextCost;
        
        savestats()
    end
    
    stats.gradnorms = stats.gradnorms(1,1:iter+1);
    stats.alphas = stats.alphas(1,1:iter+1);
    stats.costs = stats.costs(1,1:iter+1);
    stats.stepsizes = stats.stepsizes(1,1:iter+1);
    stats.xHistory= stats.xHistory(1,1:iter+1);
    stats.time = toc(timetic);
    if existsAssumedoptX
        stats.distToAssumedOptX = stats.distToAssumedOptX(1, 1:iter+1);
    end
    finalX = xCur;
    
    function savestats()
        stats.gradnorms(1, iter+1)= xCurGradNorm;
        stats.alphas(1, iter+1) = alpha;
        stats.stepsizes(1, iter+1) = stepsize;
        stats.costs(1, iter+1) = xCurCost;
        if existsAssumedoptX
            stats.distToAssumedOptX(1, iter+1) = M.dist(xCur, options.assumedoptX);
        end
        stats.xHistory{iter+1} = xCur;
    end

end

function dir = getDirection(M, xCur, xCurGradient, sHistory, yHistory, rhoHistory, scaleFactor, k)
    q = xCurGradient;
    inner_s_q = cell(1, k);
    for i = k : -1: 1
        inner_s_q{i} = rhoHistory{i}*M.inner(xCur, sHistory{i},q);
        q = M.lincomb(xCur, 1, q, -inner_s_q{i}, yHistory{i});
    end
    r = M.lincomb(xCur, scaleFactor, q);
    for i = 1: k
         omega = rhoHistory{i}*M.inner(xCur, yHistory{i}, r);
         r = M.lincomb(xCur, 1, r, inner_s_q{i}-omega, sHistory{i});
    end
    dir = M.lincomb(xCur, -1, r);
end


function [costNext, t, fail, lsiters] = linesearchnonsmooth(problem, M, xCur, d, f0, df0, c1, c2)
    alpha = 0;
    fail = 0;
    beta = inf;
    t = 1;
    max_counter = 100;
    counter = max_counter;
    while counter > 0
        xNext = M.retr(xCur, d, t);
        if (getCost(problem, xNext) > f0 + df0*c1*t)
            beta = t;
        elseif diffretractionOblique(problem, M, t, d, xCur, xNext) < c2*df0
            alpha = t;
        else
            break;
        end
        if (isinf(beta))
            t = alpha*2;
        else
            t = (alpha+beta)/2;
        end
        counter = counter - 1;
    end
    if counter == 0
        fprintf('Failed LS \n');
        fail = 1;
    end
    costNext = getCost(problem, xNext);
    lsiters = max_counter - counter + 1;
end


function slope = diffretractionOblique(problem, M, alpha, p, xCur, xNext)
    [n, m] = size(p);
    diffretr = zeros(n, m);
    for i = 1 : m
        d = p(:, i);
        dInner = d.' * d;
        diffretr(:,i) = (d-alpha*dInner*xCur(:, i)) /sqrt((1+dInner * alpha^2)^3);
    end
    %Can be optimized.
    slope = M.inner(xNext, problem.reallygrad(xNext), diffretr);
%     slope = M.inner(xNext, getGradient(problem, xNext), diffretr);
end
