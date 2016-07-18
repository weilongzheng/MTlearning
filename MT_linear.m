classdef MT_linear < MT_baseclass
    
    properties(GetAccess = 'public', SetAccess = 'private')
        % vector that contains unique labels for prediction
        labels
        % optional dimensionality reduction matrix
        W
        % weight vector for classification
        w
        % binary flag for dimensionality reduction
        dimReduce
        % binary flag for LDA labelling
%         LDA
        % parameters for convergence
        maxItVar % maximum variation between iterations before convergence
        maxNumVar % maximum number of dimensions allowed to not converge
    end
    
    methods
        function obj = MT_linear(varargin)
            % Constructor for multitask linear regression. 
            %
            % Input:
            %     Xcell: cell array of datasets
            %     ycell: cell array of labels
            %     varargin: Flags 

            % construct superclass
            obj@MT_baseclass(varargin{:})
            
            obj.dimReduce = invarargin(varargin, 'dim_reduce');
            if isempty(obj.dimReduce)
                obj.dimReduce = 0;
            end
            obj.maxItVar = invarargin(varargin,'max_it_var');
            if isempty(obj.maxItVar)
                obj.maxItVar = 1e-2;
            end
            obj.maxNumVar = invarargin(varargin,'max_pct_var');
            if isempty(obj.maxNumVar)
                obj.maxNumVar = 1e-2;
            end
            
        end
        
        function [] = init_prior(obj)
            obj.prior.mu = zeros(size(obj.w));
            obj.prior.sigma = eye(length(obj.w));
        end
        
        function prior = fit_prior(obj, Xcell, ycell)
            % sanity checks
            assert(length(Xcell) == length(ycell), 'unequal data and labels arrays');
            assert(length(Xcell) > 1, 'only one dataset provided');
            for i = 1:length(Xcell)
                assert(size(Xcell{i},2) == length(ycell{i}), 'number of datapoints and labels differ');
                ycell{i} = reshape(ycell{i},[],1);
            end
            
            
            assert(length(unique(cat(1,ycell{:}))) == 2, 'more than two classes present in the data');
            obj.labels = [unique(cat(1,ycell{:})),[1;-1]];
            % replace labels with {1,-1} for algorithm
            for i = 1:length(ycell)
                ycell{i} = MT_baseclass.swap_labels(ycell{i}, obj.labels, 'to');
            end
            obj.w = zeros(size(Xcell{1},1),1);
            
            if obj.dimReduce
                Xall = cat(2,Xcell{:});
                Xcov = cov((Xall-kron(mean(Xall,2),ones(1,size(Xall,2))))');
                [V,D] = eig(Xcov);
                if min(diag(D)) > 0
                    D = D / sum(sum(D));
                    V = V(:,diag(D)>1e-8);
                else
                    D2 = D(:,diag(D)>0);
                    D = D / sum(sum(D2));
                    V = V(:,diag(D)>1e-8);
                end
                obj.W = V;
                for i = 1:length(Xcell)
                    Xcell{i} = obj.W'*Xcell{i};
                end
                obj.w = zeros(size(obj.W,2),1);
            else
                obj.W = [];
            end
            prior = fit_prior@MT_baseclass(obj, Xcell, ycell);
        end
        
        function [b, converged] = convergence(obj, prior, prev_prior)
            mu = abs(prior.mu);
            mu_prev = abs(prev_prior.mu);
            converged = sum(or(mu > (mu_prev+obj.maxItVar*mu_prev), mu < (mu_prev - obj.maxItVar * mu_prev)));
            b = converged < (obj.maxNumVar * length(mu));
        end
        
        function [w, error] = fit_model(obj, X, y, lambda)
            Ax=obj.prior.sigma*X;
            w = ((1 / lambda)*Ax*X'+eye(size(X,1)))\((1 / lambda)*Ax*y + obj.prior.mu);
            error = obj.loss(w, X, y);
        end
        
        function out = fit_new_task(obj, X, y, varargin)
            % argument parsing
            
            ML = invarargin(varargin,'ml');
            if isempty(ML)
                ML = 0;
            end
            out = struct();
            
            if obj.dimReduce
                X = obj.W'*X;
            end

            % switch input labels using instance dictionary
            y_train = MT_baseclass.swap_labels(y, obj.labels,'to');
            if ML
                prev_w = ones(size(X,1),1);
                out.lambda = 1;
                out.loss = 1;
                count = 0;
                out.w = zeros(size(X,1),1);
                while sum(or(abs(out.w) > (prev_w+obj.maxItVar*prev_w), abs(out.w) < (prev_w - obj.maxItVar * prev_w)))...
                         && count < obj.nIts
                    prev_w = abs(out.w);
                    [out.w, out.loss] = obj.fit_model(X, y_train, out.lambda);
                    out.lambda = 2*out.loss;
                    count = count+1;
                    if obj.verbose
                    fprintf('[new task fitting] ML lambda Iteration %d, lambda %.4e \n', count, out.lambda);
                    end
                end
            else
                out.lambda = lambdaCV(@(X,y,lambda)(obj.fit_model(X{1},y{1},lambda)),...
                    @(w, X, y)(obj.loss(w, X{1}, y{1})),{X},{y_train});
                [out.w, out.loss] = obj.fit_model(X, y_train, out.lambda);
            end
            if obj.dimReduce
                out.predict = @(X)(obj.predict(out.w, obj.W'*X, obj.labels));
            else
                out.predict = @(X)(obj.predict(out.w, X, obj.labels));
            end
            out.training_acc = mean(y == out.predict(X));
        end
        
        function [] = update_prior(obj, outputCell)
            W = cat(2,outputCell{:});
            obj.prior = MT_baseclass.update_gaussian_prior(W, obj.trAdjust);
            
            if obj.dimReduce
                obj.prior.mu = obj.W*obj.prior.mu;
                obj.prior.sigma = obj.W*obj.prior.mu*obj.W';
            end
        end
        
    end
    
    methods(Static)
        function L = loss(w, X, y)
            % implements straight (average) squared loss
            L = (norm(X'*w-y,2)^2)/length(y);
        end
        
        function y = predict(w, X, labels)
            y = MT_baseclass.swap_labels(sign(X'*w), labels, 'from');
        end
        
    end
end