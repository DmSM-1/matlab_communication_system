classdef ofdm_simulator < handle

    properties
        chan
        stf
        py_stf
        ltf
        data_handler
        stf_h
        Fc
        Fs
        crc
        snr

        cfo_enable
        sfp_enable
        ltf_eqv_enable
        sdr_gain
        
        Config
        sdr_order
        OutputDir 
        graph_output

        names           
        alpha           
        beta      
        soft       
        Nvpil          
        est_method    
        metric  

        audio
        audio_path
        player 
    end

    methods
        function obj = ofdm_simulator(options)
            arguments
                % --- System / Path Parameters ---
                options.OutputDir (1,1) string = "Results/Experiment_01"
                
                % --- Global Parameters ---
                options.N (1,1) double = 1024
                options.L (1,1) double = 32
                options.Fs (1,1) double = 20e6
                
                % --- Channel Parameters ---
                options.ChanModel char = 'Model-B'
                options.dist (1,1) double = 10
                options.Fc (1,1) double = 2.4e9
                options.SNR (1,1) double = 100
                options.CFO (1,1) double = 10000
                options.max_random_sto (1,1) double = 10000
                options.sdr_gain (1,1) double = 2^12
                
                % --- STF Parameters ---
                options.stf_Ppos = [] 
                options.stf_margin1 (1,1) double = 1
                options.stf_est_symb (1,1) double = 20
                options.stf_margin2 (1,1) double = 1
                options.stf_mask_width (1,1) double = 30
                options.stf_threshold (1,1) double = 3.0
                
                % --- LTF Parameters ---
                options.ltf_Nsymb (1,1) double = 12
                options.ltf_sto_shift (1,1) int32 = 0
                
                % --- Data Parameters ---
                options.Bw (1,1) double = 0.5
                options.Npil (1,1) double = 10
                options.pilAmpl (1,1) double = 1
                options.Ndat (1,1) double = 512
                options.data_Nsymb (1,1) double = 2000
                options.Mod_pow (1,1) double = 4
                options.Cod_rate (1,1) double = 1
                options.debug (1,1) logical = true
                options.guards = []
                options.DC_guard (1,1) int32 = 1
                options.win_slope (1,1) double = 0
                options.h_len (1,1) double = 16
                options.sdr_order (1,1) int32 = 1
                options.check_crc (1,1) logical = true
                options.est_period (1,1) int32 = 1

                % --- Graph parameters ---
                options.graph_output = []

                % --- Variables ---
                options.names        = []
                options.alpha        = []
                options.beta         = []
                options.soft         = []
                options.est_method   = []
                options.metric       = []
                options.Nvpil        = []

                % --- Compensation ---
                options.cfo_enable = true
                options.sfo_enable = true
                options.ltf_eqv_enable = true

                options.audio = false
                options.audio_path = 'FlyMeToTheMoon_mono.wav';
            end

            obj.Fc = options.Fc;
            obj.Fs = options.Fs;
            obj.sdr_order = options.sdr_order;
            obj.sdr_gain = options.sdr_gain;
            obj.crc = options.check_crc;
            obj.cfo_enable = options.cfo_enable;
            obj.snr = options.SNR;
            obj.player = [];

            obj.names       = options.names;
            obj.alpha       = options.alpha;
            obj.beta        = options.beta;
            obj.soft        = options.soft;
            obj.est_method  = options.est_method;
            obj.metric      = options.metric;
            obj.Nvpil       = options.Nvpil;

            
            obj.OutputDir = options.OutputDir;
            obj.graph_output = options.graph_output;
            obj.ltf_eqv_enable = options.ltf_eqv_enable;

            obj.audio = options.audio;
            obj.audio_path = options.audio_path;

            if ~exist(obj.OutputDir, 'dir')
                mkdir(obj.OutputDir);
            end
            
            if isempty(options.stf_Ppos)
                options.stf_Ppos = [0.25, 0.75] * options.N + 1;
            end
            
            obj.Config = options;

            configPath = fullfile(obj.OutputDir, 'config.mat');
            save(configPath, 'options');
            


            obj.chan = Channel( ...
                Model = options.ChanModel, ...
                dist  = options.dist, ...
                Fc    = options.Fc, ...
                Fs    = options.Fs, ...
                SNR   = options.SNR, ...
                CFO   = options.CFO, ...
                max_random_sto = options.max_random_sto ...
            );

            obj.stf = STF( ...
                options.N, options.L, ...
                Ppos           = options.stf_Ppos, ...
                margin1        = options.stf_margin1, ...
                est_symb       = options.stf_est_symb, ...
                margin2        = options.stf_margin2, ...
                det_mask_width = options.stf_mask_width, ...
                det_threshold  = options.stf_threshold ...
            );

            obj.stf_h = STF_Handler(obj.stf);

            % system(sprintf("python3 STF.py %d %d %d %d %d %d %f", ...
            %     options.N, ...
            %     options.L, ...
            %     options.stf_est_symb, ...
            %     options.stf_margin1, ...
            %     options.stf_margin2, ...
            %     options.stf_mask_width, ...
            %     options.stf_threshold ...
            % ));

            obj.py_stf = py.STF.STF( ...
                options.N, ...
                options.L, ...
                options.stf_est_symb, ...
                options.stf_margin1, ...
                options.stf_margin2, ...
                options.stf_mask_width, ...
                options.stf_threshold, ...
                options.stf_Ppos ...
            );

            obj.ltf = LTF( ...
                options.N, options.L, ...
                Nsymb = options.ltf_Nsymb, ...
                sto_shift=options.ltf_sto_shift, ...
                bw=options.Bw ...
            );

            
            obj.data_handler = DATA_Handler( ...
                N        = options.N, ...
                L        = options.L, ...
                Bw       = options.Bw, ...
                Npil     = options.Npil, ...
                pilAmpl  = options.pilAmpl, ...
                Ndat     = options.Ndat, ...
                Nsymb    = options.data_Nsymb, ...
                Mod_pow  = options.Mod_pow, ...
                Cod_rate = options.Cod_rate, ...
                guards   = options.guards, ...
                DC_guard = options.DC_guard, ...
                win_slope= options.win_slope, ...
                h_len    = options.h_len, ...
                est_period = options.est_period, ...
                debug    = options.debug   ...
            );
            
            fid = fopen("config.txt", 'w');
            fprintf(fid,'fft_size = %d\n', obj.data_handler.N);
            fprintf(fid,'num_data_subc = %d\n', obj.data_handler.Ndat);
            fprintf(fid,'num_pilot_subc = %d\n', obj.data_handler.Npil);
            fprintf(fid,'cp_size = %d\n', obj.data_handler.L);
            fprintf(fid,'num_symb = %d\n', obj.data_handler.Nsymb);

            fprintf(fid,'bw_hz = %d\n', 10000000);
            fprintf(fid,'fs_hz = %d\n', obj.Fs);
            fprintf(fid,'lo_hz = %d\n', obj.Fc);
            fprintf(fid,'hardwaregain = %d\n', 50);
            fprintf(fid,'mult = %d\n', 1);
            fprintf(fid,'rx_buf_size = %d\n', 10);
            fprintf(fid,'tx_cycle_buf = %d\n', 0);
            fprintf(fid,'tx_time_int = %d\n', 0);
            fprintf(fid,'iterations = %d\n', 10000);
            fclose(fid);

        end

        function [tx_waveform, coded_bits] = generate_frame(obj, seed, options)
            arguments
                obj
                seed = [] 
                options.iter = 1
            end

            source_bits = [];

            if obj.audio
                [y, Fs] = audioread(obj.audio_path, [obj.data_handler.payload/16*(options.iter-1)+1, obj.data_handler.payload/16*options.iter]);
                y = int16(2^15.*y);
                source_bits = double(de2bi(typecast(y, 'uint16'), 16, 'left-msb'));
                source_bits = reshape(source_bits, obj.data_handler.payload_per_symbol, []);
                source_bits = xor(source_bits, obj.data_handler.scrambler);
                source_bits = double(source_bits(:));

            else
                if ~isempty(seed)
                    rng(seed);
                end
                source_bits = randi([0, 1], obj.data_handler.payload, 1);
            end

            coded_bits = obj.data_handler.generate_data(source_data=source_bits);

            data_wav = obj.data_handler.get_waveform(coded_bits);
            tx_mod_symbols = obj.data_handler.mod_data;
            tx_waveform = [reshape(double(obj.stf.waveform), [], 1); obj.ltf.waveform; data_wav];

            
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            
            if isempty(validNums)
                nextIdx = 1;
            else
                nextIdx = max(validNums) + 1;
            end
            
            
            newDirName = num2str(nextIdx);
            currentSaveDir = fullfile(obj.OutputDir, newDirName);
            
            mkdir(currentSaveDir);
            
            savePath = fullfile(currentSaveDir, 'tx_data.mat');
            
            save(savePath, 'tx_waveform', 'coded_bits', 'source_bits', 'tx_mod_symbols');
        end
        
        function run_channel_on_dataset(obj)
            % RUN_CHANNEL_ON_DATASET Сканирует папку OutputDir, находит все

            % fprintf('--- Start Channel Simulation on Dataset ---\n');
            % fprintf('Target Directory: %s\n', obj.OutputDir);

            % 1. Сканируем папку на наличие числовых подпапок
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            validNums = sort(validNums);

            if isempty(validNums)
                warning('No numbered folders found in directory!');
                return;
            end

            totalFolders = length(validNums);
            fprintf('Found %d folders. Processing...\n', totalFolders);

            reverseStr = ''; 

            for i = 1:totalFolders
                tic;
                folderIdx = validNums(i);
                
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                txFile = fullfile(currentDir, 'tx_data.mat');
                rxFile = fullfile(currentDir, 'rx_data.mat');
                
                if exist(txFile, 'file')
                    loadedData = load(txFile, 'tx_waveform');
                    
                    if isfield(loadedData, 'tx_waveform')
                        rx_waveform = obj.chan.tx(loadedData.tx_waveform);
                        
                        save(rxFile, 'rx_waveform');
                    else
                        fprintf('\nWarning: Folder %d does not contain tx_waveform variable.\n', folderIdx);
                    end
                else
                    fprintf('\nWarning: tx_data.mat not found in folder %d.\n', folderIdx);
                end
                
                msg = sprintf('Processed: %d / %d (Folder ID: %d) %f s', i, totalFolders, folderIdx, toc());
                fprintf([reverseStr, msg]);
                reverseStr = repmat('\b', 1, length(msg));
            end
            
        end

        function waveform = recv(obj, STA2, tx_len)
            STA2.recv(); %захватываем данные в буффер
            STA2.recv(); %сдвинули буффер
            STA2.recv(); %сдвинули буффер

            buffer_size = double(STA2.buffer_size);
            buf = zeros(buffer_size*2, 1);
            
            stf_len = length(obj.stf.waveform);
            detect = 0;

            buf(buffer_size+1:end, :) = STA2.recv().';
            for k = 1:10
                buf(1:buffer_size, :) = buf(buffer_size+1:end, :);
                buf(buffer_size+1:end, :) = STA2.recv().';
                detect = obj.stf_h.detect(buf(1:buffer_size+stf_len, :));
                obj.stf_h.sto = max(1, obj.stf_h.sto-2*stf_len);
                if detect
                    waveform = buf(obj.stf_h.sto : min(2*buffer_size, obj.stf_h.sto+tx_len+2*stf_len), :);
                    break;
                end
            end
            
            if ~detect
                waveform = [];
            end
        end

        function run_sdr_channel_on_dataset(obj, options)
            arguments
                obj 
                options.folder = 0
            end
            % RUN_CHANNEL_ON_DATASET Сканирует папку OutputDir, находит все

            fprintf('--- Start SDR Channel on Dataset ---\n');

            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            
            validNums = sort(validNums);

            if isempty(validNums)
                warning('No numbered folders found in directory!');
                return;
            end

            totalFolders = length(validNums);
            fprintf('Found %d folders. Processing...\n', totalFolders);

            reverseStr = ''; 

            adr = ['ip:192.168.4.1'; 'ip:192.168.3.1'];

            if obj.sdr_order
                adr = ['ip:192.168.3.1'; 'ip:192.168.4.1'];
            end

            python = true;
            STA1 = [];
            STA2 = [];

            if python
                STA1 = py.sdr.SDR( ...
                    adr(1,:), ...
                    obj.Fc, ...
                    obj.Fs, ...
                    tx_cycle_buffer = false, ...
                    buffer_size = 65536, ...
                    tx_hardwaregain_chan0 = 0, ...
                    rx_hardwaregain_chan0 = 50);
    
                STA2 = py.sdr.SDR( ...
                    adr(2,:), ...
                    obj.Fc, ... 
                    obj.Fs,...%+35, ...
                    buffer_size = STA1.buffer_size*10, ...
                    tx_hardwaregain_chan0 = 0, ...
                    rx_hardwaregain_chan0 = 50, ...
                    stf=obj.py_stf);

                % STA2.recv();
                
                % Короче читай мануал к libiio, там было сказано про использовании на rx нескольких буфферов. 
                % При первом запуске как бы используется первый, но при последующих самые новые данные лежат только в "последнем"
            else
                sdr_mex('init', int32(0), int32(2^20), 'config.txt');
                sdr_mex('init', int32(1), int32(2^20), 'config.txt');
            end

            reverseStr = '';

            for i = 1:totalFolders
                tic;

                if options.folder
                    i = options.folder;
                end

                folderIdx = validNums(i);

                % Формируем пути
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                txFile = fullfile(currentDir, 'tx_data.mat');
                rxFile = fullfile(currentDir, 'rx_data.mat');

                
                if exist(txFile, 'file')
                    loadedData = load(txFile, 'tx_waveform');

                    if isfield(loadedData, 'tx_waveform')
                            
                        tx_waveform = (loadedData.tx_waveform).*obj.sdr_gain;
                        
                        % pause(1);

                        STA1.send([zeros(1,1*STA1.buffer_size), tx_waveform.']);
                        rx_waveform = double(STA2.recv_det(length(tx_waveform))).';
                        
                        save(rxFile, 'rx_waveform');
                    else
                        fprintf('\nWarning: Folder %d does not contain tx_waveform variable.\n', folderIdx);
                    end
                else
                    fprintf('\nWarning: tx_data.mat not found in folder %d.\n', folderIdx);
                end

                msg = sprintf('Processed: %d / %d (Folder ID: %d) %3.6f s', i, totalFolders, folderIdx, toc);
                fprintf([reverseStr, msg]);
                reverseStr = repmat('\b', 1, length(msg));

                if options.folder
                    break
                end
            end

            sdr_mex('del', int32(0));
            sdr_mex('del', int32(1));

            if python
                delete(STA1);
                delete(STA2);
            else
                sdr_mex('del', int32(0));
                sdr_mex('del', int32(1));
            end
        end


        function generate_dataset(obj, num_frames, options)
            arguments
                obj
                num_frames (1,1) double {mustBePositive, mustBeInteger}
                options.seed = []
            end

            
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir]; 
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            
            folderNums = str2double(folderNames);
            isNumberedFolder = ~isnan(folderNums); 
            
            foldersToDelete = folderNames(isNumberedFolder);

            if ~isempty(foldersToDelete)
                fprintf('Cleaning up %d old data folders...\n', length(foldersToDelete));
                for k = 1:length(foldersToDelete)
                    folderPath = fullfile(obj.OutputDir, foldersToDelete{k});
                    rmdir(folderPath, 's'); 
                end
            else
                fprintf('Directory is clean. No numbered folders found.\n');
            end

            
            reverseStr = ''; 
            t_start = tic;

            for i = 1:num_frames
                msg = sprintf('Generating: %3d / %d', i, num_frames);
                fprintf([reverseStr, msg]);
                if ~isempty(options.seed)
                    obj.generate_frame(options.seed(mod(i-1, length(options.seed))+1), "iter",i);
                else
                    obj.generate_frame(i, iter=i);
                end
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            t_total = toc(t_start);
            fprintf('\n');
            % fprintf('\nDone! Total time: %.2f s\n', t_total);
        end


        function [err, ferr, ber, fber, abs_err, mse] = get_metric(obj, rx_res_data, decoded_res_data, rx_eqv_data, tx_struct)
            err     = xor(rx_res_data(:), tx_struct.coded_bits(:));
            ferr    = xor(decoded_res_data(:), tx_struct.source_bits(:));
            ber     = mean(err);
            fber    = mean(ferr);

            err     = reshape(err,      [], obj.data_handler.Nsymb);
            ferr    = reshape(ferr,  [], obj.data_handler.Nsymb);
            abs_err = abs(rx_eqv_data - tx_struct.tx_mod_symbols);
            mse     = mean(abs_err(:).^2);
        end


        function process_dataset(obj, options)
            arguments
                obj 
                options.folder = 0
            end

            fprintf('\nProcessing Dataset (Rx Analysis) ...\n');

            % 1. SCAN DIRECTORIES
            files = dir(obj.OutputDir);
            subDirs = files([files.isdir]);
            folderNames = {subDirs.name};
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = sort(folderNums(~isnan(folderNums)));

            if isempty(validNums)
                warning('No data folders found!');
                return;
            end
            
            totalFrames = length(validNums);
            
            % 2. INIT STF&LTF handlers

            ltf_h = LTF_Handler(obj.ltf, h_window=4*obj.Config.L, debug=false);
            
            % HEADER TITLE
            fprintf('| %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s |\n', 'ID', 'SNR', 'STF SNR', 'BER', 'FEC BER', 'MSE', 'Status', 'TIME');

            avg_s_ber = 0;
            avg_s_fec_ber = 0;
            avg_s_mse = 0;
            avg_stf_snr = 0;
            valid_count = 0;

            if any(obj.graph_output==1) fig1 = figure(1); end
            if any(obj.graph_output==2) fig2 = figure(2); end
            if any(obj.graph_output==3) fig3 = figure(3); end

            % 3. RECEIVER LOOP
            for i = 1:totalFrames
                tic;

                if options.folder
                    i = options.folder;
                end

                folderIdx = validNums(i);
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                
                rxFile = fullfile(currentDir, 'rx_data.mat');
                txFile = fullfile(currentDir, 'tx_data.mat');
                
                % CHECK FILE EXISTANCE
                if ~exist(rxFile, 'file') || ~exist(txFile, 'file')
                    fprintf('| %8d | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s |\n', folderIdx, '-', '-', '-', '-', '-', '-', '-', 'NO FILE');
                    continue;
                end
                
                % LOAD DATA
                rx_struct = load(rxFile, 'rx_waveform');
                tx_struct = load(txFile, 'tx_waveform', 'coded_bits', 'source_bits', 'tx_mod_symbols');
                
                rx_waveform = rx_struct.rx_waveform;
                
                % --- RECEIVER PIPELINE ---
                
                %STF Detection & CFO, SNR estimation
                % py_stf_h = py.STF.Handler(obj.py_stf);
                % detect = py_stf_h.detect(rx_waveform);

                % disp(py_stf_eh.sto);

                detect = obj.stf_h.detect(rx_waveform);

                if ~detect
                    fprintf('| %8d | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s |\n', folderIdx, '-', '-', '-', '-', '-', '-', '-', 'FAIL:STF');
                    continue;
                end

                avg_stf_snr = avg_stf_snr + obj.stf_h.snr;
                
                rx_frame = rx_waveform(obj.stf_h.sto : min(length(rx_waveform), obj.stf_h.sto + length(tx_struct.tx_waveform)));

                if obj.cfo_enable
                    rx_frame = rx_frame .* exp(-2i*pi * obj.stf_h.cfo * (0 : length(rx_frame)-1).');
                end
                
                %LTF Estimation 
                sto = ltf_h.find_sto(rx_frame);

                rx_data_wav = rx_frame(sto : end);
                
                [cfo, sfo] = obj.data_handler.get_freq(rx_data_wav);
                phase = 0;
                for j = 1:length(rx_frame)
                    phase = phase + cfo;
                    rx_frame(j) = rx_frame(j)*exp(-1i*phase);
                end
                est = ltf_h.estimate(rx_frame, sfo=sfo, beta=obj.data_handler.beta);
                
                
                if ~est
                     fprintf('| %8d | %8s | %8s | %8s | %8s | %8s | %8s | %8s | %8s |\n', folderIdx, '-', '-', '-', '-', '-', '-', '-', 'FAIL:LTF');
                     continue;
                end
                
                %Data Processing
                rx_data_wav = rx_frame(ltf_h.sto : end);
                
                if ~obj.ltf_eqv_enable
                    ltf_h.eqv = complex(ones(size(ltf_h.eqv)));
                end

                ltf_eqv = obj.data_handler.set_eqv(ltf_h);
                obj.data_handler.alpha = obj.alpha(1);
                obj.data_handler.beta  = obj.beta(1);
                obj.data_handler.soft  = obj.soft(1);
                obj.data_handler.est_method = obj.est_method(1);
                obj.data_handler.metric = obj.metric(1);
                obj.data_handler.Nvpil = obj.Nvpil(1);

                [s_rx_eqv_data, s_rx_eqv_pilots, s_ifft_data, s_rx_res_data, s_decoded_res_data] = obj.data_handler.get_frames(rx_data_wav, snr=obj.stf_h.snr);
                [s_err, s_ferr, s_ber, s_fber, s_abs_err, s_mse] = get_metric(obj, s_rx_res_data, s_decoded_res_data, s_rx_eqv_data, tx_struct);
                
                avg_s_ber = avg_s_ber + s_ber;
                avg_s_fec_ber = avg_s_fec_ber + s_fber;
                avg_s_mse = avg_s_mse + s_mse;
                valid_count = valid_count + 1;
               
                
                %RESULTS
                    %CONSOL OUTPUT
                    
                    
                    %SAVE RESULTS IN CVS
                    csvPath = fullfile(obj.OutputDir, 'statistics.csv');
                    
                    % if exist(csvPath, "file")
                    %     delete(csvPath);
                    % end
                    new_file = ~isfile(csvPath);
                    fid = fopen(csvPath, 'a');

                    if fid ~= -1
                        if valid_count == 1 & new_file
                            fprintf(fid, 'FolderID, MOD_POW, SNR, MS_SNR');

                            for name = obj.names
                                fprintf(fid, ', %s_BER, %s_FEC_BER, %s_MSE', name, name, name);
                            end
                        end

                        fprintf(fid, '\n%d,%f,%f,%f,', folderIdx, obj.data_handler.Mod_pow,  obj.snr, obj.stf_h.snr);

                        fprintf(fid, '%f,%f,%f', s_ber, s_fber, s_mse);

                        for k = 2:length(obj.names)
                            ltf_eqv = obj.data_handler.set_eqv(ltf_h);
                            obj.data_handler.alpha = obj.alpha(mod(k, length(obj.alpha)));
                            obj.data_handler.beta  = obj.beta(mod(k, length(obj.beta)));
                            obj.data_handler.soft  = obj.soft(mod(k, length(obj.soft)));
                            obj.data_handler.est_method = obj.est_method(mod(k, length(obj.est_method)));
                            obj.data_handler.metric = obj.metric(mod(k, length(obj.metric)));
                            obj.data_handler.Nvpil = obj.Nvpil(mod(k, length(obj.Nvpil)));

                            [rx_eqv_data, rx_eqv_pilots, ifft_data, rx_res_data, decoded_res_data] = obj.data_handler.get_frames(rx_data_wav, snr=obj.stf_h.snr);
                            [err, ferr, ber, fber, abs_err, mse] = get_metric(obj, rx_res_data, decoded_res_data, rx_eqv_data, tx_struct);
                            

                            fprintf(fid, ',%f,%f,%f', ber, fber, mse);
                        end

                        fprintf(fid,'\n');

                        fclose(fid);
                    end

                    fprintf('| %8d | %8.4f | %8.4f | %8.5f | %8.5f | %8.5f | %8s | %8.5f |\n', ...
                        folderIdx, obj.snr, obj.stf_h.snr, s_ber, s_fber, s_mse, 'OK', toc);

                if obj.audio
                    s_decoded_res_data = reshape(s_decoded_res_data, obj.data_handler.payload_per_symbol, []);
                    s_decoded_res_data = xor(s_decoded_res_data, obj.data_handler.scrambler);
                    s_decoded_res_data = double(s_decoded_res_data(:));

                    bits = reshape(s_decoded_res_data, [], 16); 
                    y_uint = uint16(bi2de(int8(bits), 'left-msb'));
                    y = double(typecast(y_uint, 'int16'))./2^15;
                    if i == 1
                        audiowrite("res.wav",y,44100);
                    end
                    % sound(y, 44100);
                    
                    
                    if ~isempty(obj.player)
                        while isplaying(obj.player)
                            pause(0.01); 
                        end
                    end

                    obj.player = audioplayer(y, 44100);
                    play(obj.player);


                end
                
                %PLOTS
                %DUMP
                if any(obj.graph_output==1)
                    set(0, 'CurrentFigure', fig1);
                        clf;
                        t = tiledlayout(fig1, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        
                        nexttile;
                        plot(abs(rx_waveform));
                        title("Signal amplitude");
        
                        nexttile;
                        plot(obj.data_handler.ang);
                        title("Pilot phase diviation");
        
                        nexttile;
                        plot(abs(ltf_eqv));
                        title("LTF AFC");
                        nexttile;
                        plot(unwrap(angle(ltf_eqv)));
                        title("LTF PFC");
        
                        nexttile;
                        plot(abs(obj.data_handler.eqv(obj.data_handler.activeIdx)));
                        title("Last symb AFC");
                        nexttile;
                        plot(unwrap(angle(obj.data_handler.eqv)));
                        title("Last symb PFC");

                        nexttile;
                        plot(obj.data_handler.std_eqv_err);
                        title("STD error of AFC");
                        nexttile;
                        plot(abs(ltf_h.h(1:2*obj.data_handler.L)));
                        title("channel impulse response");

                end
                %SPECTROGRAM & IQ
                if any(obj.graph_output==2)
                    set(0, 'CurrentFigure', fig2);
                        clf;
                        t = tiledlayout(fig2, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
                        hold on;
                        
                        nexttile;
                        spectrogram(rx_waveform, obj.Config.N, [], 'yaxis', 'centered');
                        max_val = max(10*log10(abs(rx_waveform).^2));
                        clim([max_val-50, max_val]);
                        title(sprintf('Frame %d Spectrogram', folderIdx));

                        nexttile;
                        ifft_data_plot = s_ifft_data ./ sqrt(mean(abs(s_ifft_data.^2), 'all'));
                        scatter(real(ifft_data_plot(:)), imag(ifft_data_plot(:)), 3, 'blue', '.');
                        hold on;
                        scatter(real(s_rx_eqv_data(:)), imag(s_rx_eqv_data(:)), 3, 'red', '.');
                        scatter(real(s_rx_eqv_pilots(:)), imag(s_rx_eqv_pilots(:)), 7, 'green', '.');
                        hold off;

                        xlim([-2, 2]);
                        ylim([-2, 2]);
                        axis("square");
                        grid on;
                        title(sprintf('Constellation (BER: %.1e)', s_ber));
                          
                end
                
                %ABS ERROR
                if any(obj.graph_output==3)
                    set(0, 'CurrentFigure', fig3);
                        clf;
    
                        if isappdata(fig3, 'graphics_linkprop1')
                            rmappdata(fig3, 'graphics_linkprop1'); 
                        end
                        if isappdata(fig3, 'graphics_linkprop2')
                            rmappdata(fig3, 'graphics_linkprop2')
                        end
    
                        t = tiledlayout(fig3, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        
                        ax1 = nexttile;
                        mesh(ax1, s_abs_err);
                        title(ax1, sprintf('Frame %d MSE (id)', folderIdx));
                        colormap(ax1, 'jet');    
                        axis(ax1, 'xy');            
                        xlabel(ax1, 'Time / Index');
                        ylabel(ax1, 'Frequency / Range');
                        zlim(ax1, [0, 1]);
                        clim(ax1, [0, 1]);
                        axis("square");

                        ax2 = nexttile;
                        imagesc(ax2, s_err);
                        title(ax2, sprintf('Frame %d BER', folderIdx));
                        colormap(ax2, 'gray');    
                        axis(ax2, 'xy');            
                        axis("square");
                        xlabel(ax2, 'Time / Index');
                        
                        ax3 = nexttile;
                        imagesc(ax3, s_ferr);
                        title(ax3, sprintf('Frame %d FEC BER', folderIdx));
                        colormap(ax3, 'gray');    
                        axis(ax3, 'xy'); 
                        axis("square");
                        xlabel(ax3, 'Time / Index');
                        ylabel(ax3, 'Frequency / Range');

                        plotPath = fullfile(currentDir, 'analysis_plot.png');
                        exportgraphics(fig3, plotPath, 'Resolution', 300);
                        
                end

                if options.folder
                    break
                end
            end
            
            if valid_count > 0
                fprintf('| %8s | %8.4f | %8.4f |%8.3e |%8.3e | %8.5f |\n', ...
                         'Avg', obj.snr, avg_stf_snr/valid_count, avg_s_ber/valid_count, avg_s_fec_ber/valid_count, avg_s_mse/valid_count);
            end
        end
        
    end
end