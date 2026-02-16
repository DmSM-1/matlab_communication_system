classdef OFDM_System < handle

    properties
        % Внутренние модули
        chan
        stf
        ltf
        data_handler
        Fc
        Fs
        crc

        cfo_enable
        sfp_enable
        ltf_eqv_enable
        
        % Конфигурация и пути
        Config
        sdr_order
        OutputDir % Путь к папке результатов
        graph_output
        
    end

    methods
        function obj = OFDM_System(options)
            arguments
                % --- System / Path Parameters ---
                options.OutputDir (1,1) string = "Results/Experiment_01" % Путь по умолчанию
                
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
                
                % --- STF Parameters ---
                options.stf_Ppos = [] 
                options.stf_margin1 (1,1) double = 1
                options.stf_est_symb (1,1) double = 20
                options.stf_margin2 (1,1) double = 1
                options.stf_mask_width (1,1) double = 30
                options.stf_threshold (1,1) double = 7.0
                
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
                options.alpha (1,1) double = 0.5
                options.beta (1,1) double = 0.5
                options.debug (1,1) logical = true
                options.guards = []
                options.DC_guard (1,1) int32 = 1
                options.win_slope (1,1) double = 0
                options.soft (1,1) logical = 0

                options.sdr_order (1,1) int32 = 1
                options.check_crc (1,1) logical = false
                options.graph_output (1,1) logical = false

                options.cfo_enable = true
                options.sfo_enable = true
                options.ltf_eqv_enable = true
            end

            obj.Fc = options.Fc;
            obj.Fs = options.Fs;
            obj.sdr_order = options.sdr_order;
            obj.crc = options.check_crc;
            obj.cfo_enable = options.cfo_enable;
            
            % 1. Управление директорией (Overwrite / Create)
            obj.OutputDir = options.OutputDir;
            obj.graph_output = options.graph_output;
            obj.ltf_eqv_enable = options.ltf_eqv_enable;
            
            if ~exist(obj.OutputDir, 'dir')
                mkdir(obj.OutputDir);
            end
            
            
            % 2. Обработка параметров
            if isempty(options.stf_Ppos)
                options.stf_Ppos = [0.25, 0.75] * options.N + 1;
            end
            
            obj.Config = options;

            % 3. Сохранение конфигурации
            % Сохраняем структуру options в файл config.mat внутри папки
            configPath = fullfile(obj.OutputDir, 'config.mat');
            save(configPath, 'options');
            

            % 4. Инициализация подсистем
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
                alpha    = options.alpha, ...
                beta     = options.beta, ...
                guards   = options.guards, ...
                DC_guard = options.DC_guard, ...
                win_slope= options.win_slope, ...
                soft     = options.soft, ...
                debug    = options.debug   ...
            );
            
        end

        function [tx_waveform, coded_bits] = generate_frame(obj, seed)
            arguments
                obj
                seed = [] 
            end

            % --- 1. Генерация данных ---
            if ~isempty(seed)
                rng(seed);
            end

            source_bits = randi([0, 1], obj.data_handler.payload, 1);
            coded_bits = obj.data_handler.generate_data(source_data=source_bits);

            % Генерируем waveform (внутри data_handler обновляется поле mod_data)
            data_wav = obj.data_handler.get_waveform(coded_bits);
            
            % ИЗВЛЕКАЕМ МОДУЛИРОВАННЫЕ СИМВОЛЫ (QAM)
            tx_mod_symbols = obj.data_handler.mod_data;
            
            % Сборка полного кадра
            tx_waveform = [obj.stf.waveform; obj.ltf.waveform; data_wav];

            % --- 2. Логика файловой системы ---
            
            % Получаем список всех папок внутри OutputDir
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir];
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            % Фильтрация имен
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            folderNums = str2double(folderNames);
            validNums = folderNums(~isnan(folderNums));
            
            % Определение следующего индекса
            if isempty(validNums)
                nextIdx = 1;
            else
                nextIdx = max(validNums) + 1;
            end
            
            % --- 3. Создание папки и сохранение ---
            
            newDirName = num2str(nextIdx);
            currentSaveDir = fullfile(obj.OutputDir, newDirName);
            
            mkdir(currentSaveDir);
            
            savePath = fullfile(currentSaveDir, 'tx_data.mat');
            
            % СОХРАНЯЕМ 3 ПЕРЕМЕННЫЕ: волну, биты и QAM-символы
            save(savePath, 'tx_waveform', 'coded_bits', 'source_bits', 'tx_mod_symbols');
        end
        
        function run_channel_on_dataset(obj)
            % RUN_CHANNEL_ON_DATASET Сканирует папку OutputDir, находит все

            fprintf('--- Start Channel Simulation on Dataset ---\n');
            fprintf('Target Directory: %s\n', obj.OutputDir);

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

            % 2. Цикл по всем найденным папкам
            reverseStr = ''; 

            for i = 1:totalFolders
                folderIdx = validNums(i);
                
                % Формируем пути
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                txFile = fullfile(currentDir, 'tx_data.mat');
                rxFile = fullfile(currentDir, 'rx_data.mat');
                
                % Проверяем наличие файла с данными передачи
                if exist(txFile, 'file')
                    % Загружаем tx_waveform
                    loadedData = load(txFile, 'tx_waveform');
                    
                    if isfield(loadedData, 'tx_waveform')
                        % --- ПРОГОН ЧЕРЕЗ КАНАЛ ---
                        rx_waveform = obj.chan.tx(loadedData.tx_waveform);
                        
                        % --- СОХРАНЕНИЕ ---
                        save(rxFile, 'rx_waveform');
                    else
                        fprintf('\nWarning: Folder %d does not contain tx_waveform variable.\n', folderIdx);
                    end
                else
                    fprintf('\nWarning: tx_data.mat not found in folder %d.\n', folderIdx);
                end
                
                % Вывод прогресса
                msg = sprintf('Processed: %d / %d (Folder ID: %d)', i, totalFolders, folderIdx);
                fprintf([reverseStr, msg]);
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            fprintf('\n--- Done ---\n');
        end

        function run_sdr_channel_on_dataset(obj)
            % RUN_CHANNEL_ON_DATASET Сканирует папку OutputDir, находит все

            fprintf('--- Start SDR Channel on Dataset ---\n');
            fprintf('Target Directory: %s\n', obj.OutputDir);

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
                folderIdx = validNums(i);
                
                % Формируем пути
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                txFile = fullfile(currentDir, 'tx_data.mat');
                rxFile = fullfile(currentDir, 'rx_data.mat');
                
                if exist(txFile, 'file')
                    loadedData = load(txFile, 'tx_waveform');
                    adr = ['ip:192.168.4.1'; 'ip:192.168.3.1'];

                    if obj.sdr_order
                        adr = ['ip:192.168.3.1'; 'ip:192.168.4.1'];
                    end

                    if isfield(loadedData, 'tx_waveform')
                        % --- ПРОГОН ЧЕРЕЗ КАНАЛ ---
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
                            buffer_size = STA1.buffer_size*100, ...
                            tx_hardwaregain_chan0 = 0, ...
                            rx_hardwaregain_chan0 = 50);

                        tx_waveform = (loadedData.tx_waveform).*2^12;

                        tx_waveform = tx_waveform.';
                        tx_waveform = [zeros(1,25*STA1.buffer_size), tx_waveform];
                        
                        STA1.send(tx_waveform);
                        rx_waveform = reshape(double(STA2.recv()), [], 1);

                        delete(STA1);
                        delete(STA2);
                                                
                        % --- СОХРАНЕНИЕ ---
                        save(rxFile, 'rx_waveform');
                    else
                        fprintf('\nWarning: Folder %d does not contain tx_waveform variable.\n', folderIdx);
                    end
                else
                    fprintf('\nWarning: tx_data.mat not found in folder %d.\n', folderIdx);
                end
                
                % Вывод прогресса
                msg = sprintf('Processed: %d / %d (Folder ID: %d)', i, totalFolders, folderIdx);
                fprintf([reverseStr, msg]);
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            fprintf('\n--- Done ---\n');
        end


        function generate_dataset(obj, num_frames)
            arguments
                obj
                num_frames (1,1) double {mustBePositive, mustBeInteger}
            end

            % Удаляем только папки с именами "1", "2", "100" и т.д.
            
            files = dir(obj.OutputDir);
            dirFlags = [files.isdir]; % Берем только папки
            subDirs = files(dirFlags);
            folderNames = {subDirs.name};
            
            % Исключаем служебные '.' и '..'
            folderNames = folderNames(~ismember(folderNames, {'.', '..'}));
            
            % Проверяем, является ли имя числом
            folderNums = str2double(folderNames);
            isNumberedFolder = ~isnan(folderNums); % Маска: true, если имя - число
            
            foldersToDelete = folderNames(isNumberedFolder);
            
            if ~isempty(foldersToDelete)
                fprintf('Cleaning up %d old data folders...\n', length(foldersToDelete));
                for k = 1:length(foldersToDelete)
                    folderPath = fullfile(obj.OutputDir, foldersToDelete{k});
                    rmdir(folderPath, 's'); % 's' удаляет папку вместе с содержимым
                end
            else
                fprintf('Directory is clean. No numbered folders found.\n');
            end

            fprintf('--- Start Data Generation ---\n');
            fprintf('Target Directory: %s\n', obj.OutputDir);
            fprintf('Payload: %d\n', obj.data_handler.payload);
            
            reverseStr = ''; 
            t_start = tic;

            for i = 1:num_frames
                msg = sprintf('Generating: %3d / %d', i, num_frames);
                fprintf([reverseStr, msg]);
                obj.generate_frame();
                reverseStr = repmat('\b', 1, length(msg));
            end
            
            t_total = toc(t_start);
            fprintf('\nDone! Total time: %.2f s\n', t_total);
        end


        function process_dataset(obj)
            % PROCESS_DATASET Загружает сохраненные rx_waveform из папок,
            % прогоняет через приемник (STF->LTF->Data) и считает ошибки.

            fprintf('--- Start Processing Dataset (Rx Analysis) ---\n');
            fprintf('Directory: %s\n', obj.OutputDir);

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
            stf_h = STF_Handler(obj.stf, debug=false);
            ltf_h = LTF_Handler(obj.ltf, h_window=4*obj.Config.L, debug=false);
            
            % HEADER TITLE
            fprintf('| %4s | %15s | %8s | %8s | %8s | %8s | %8s | %9s | %s |\n', 'ID', 'SNR (BB SNR)', 'BER(ID)','BER', 'BER(FEC)', 'RMSE(ID)', 'RMSE', 'CFO', 'Status');
            fprintf('|%s|\n', repmat('-', 1, 100));

            total_ber = 0;
            total_fec_ber = 0;
            total_rmse = 0;
            valid_count = 0;

            if obj.graph_output
                fig1 = figure(1);
                fig2 = figure(2);
                fig3 = figure(3);
                fig4 = figure(4);
                fig5 = figure(5);
            end

            % 3. RECEIVER LOOP
            for i = 1:totalFrames
                folderIdx = validNums(i);
                currentDir = fullfile(obj.OutputDir, num2str(folderIdx));
                
                rxFile = fullfile(currentDir, 'rx_data.mat');
                txFile = fullfile(currentDir, 'tx_data.mat');
                
                % CHECK FILE EXISTANCE
                if ~exist(rxFile, 'file') || ~exist(txFile, 'file')
                    fprintf('| %4d | %15s | %8s  | %8s | %8s | %8s | %8s | %8s | %s |\n', folderIdx, '-', '-', '-', '-', '-', '-', '-', 'NO FILE');
                    continue;
                end
                
                % LOAD DATA
                rx_struct = load(rxFile, 'rx_waveform');
                tx_struct = load(txFile, 'tx_waveform', 'coded_bits', 'source_bits', 'tx_mod_symbols');
                
                rx_waveform = rx_struct.rx_waveform;
                
                % --- RECEIVER PIPELINE ---
                
                %STF Detection & CFO, SNR estimation
                detect = stf_h.detect(rx_waveform);
                
                if ~detect
                    fprintf('| %4d | %15s | %8s  | %8s | %8s | %8s | %8s | %8s | %s |\n', folderIdx, '-', '-', '-', '-', '-', '-', '-', 'FAIL:STF');
                    continue;
                end
                
                rx_frame = rx_waveform(stf_h.sto : min(length(rx_waveform), stf_h.sto + length(tx_struct.tx_waveform)));

                if obj.cfo_enable
                    rx_frame = rx_frame .* exp(-2i*pi * stf_h.cfo * (0 : length(rx_frame)-1).');
                end
                
                %LTF Estimation 
                sto = ltf_h.find_sto(rx_frame);

                rx_data_wav = rx_frame(ltf_h.sto : end);
                [cfo, sfo] = obj.data_handler.get_freq(rx_data_wav);

                phase = 0;
            
                for j = 1:length(rx_frame)
                    phase = phase + cfo;
                    rx_frame(j) = rx_frame(j)*exp(-1i*phase);
                end

                est = ltf_h.estimate(rx_frame, sfo=sfo, beta=obj.data_handler.beta);
                
                if ~est
                     fprintf('| %4d | %15s | %8s | %8s | %8s | %8s | %8s | %8.2e | %s |\n', folderIdx, '-', '-', '-', '-', '-', '-', stf_h.cfo, 'FAIL:LTF');
                     continue;
                end
                
                %Data Processing
                rx_data_wav = rx_frame(ltf_h.sto : end);
                
                if ~obj.ltf_eqv_enable
                    ltf_h.eqv = complex(ones(size(ltf_h.eqv)));
                end

                ltf_eqv = obj.data_handler.set_eqv(ltf_h);
                [id_rx_eqv_data, id_rx_eqv_pilots, id_ifft_data, id_rx_res_data, decoded_id_res_data] = obj.data_handler.get_data(rx_data_wav, source=tx_struct.coded_bits, snr=stf_h.snr);
                ltf_eqv = obj.data_handler.set_eqv(ltf_h);
                [rx_eqv_data, rx_eqv_pilots, ifft_data, rx_res_data, decoded_res_data] = obj.data_handler.get_data(rx_data_wav, crc=obj.crc, snr=stf_h.snr);
                
                % ERRORS 
                err         = xor(rx_res_data(:), tx_struct.coded_bits(:));
                fec_err     = xor(decoded_res_data(:), tx_struct.source_bits(:));
                id_err      = xor(id_rx_res_data(:), tx_struct.coded_bits(:));

                ber         = mean(err);
                fec_ber     = mean(fec_err);
                id_ber      = mean(id_err);

                err         = reshape(err,      [], obj.data_handler.Nsymb);
                fec_err     = reshape(fec_err,  [], obj.data_handler.Nsymb);

                abs_err     = abs(rx_eqv_data - tx_struct.tx_mod_symbols);
                id_abs_err  = abs(id_rx_eqv_data - tx_struct.tx_mod_symbols);

                rmse        = sqrt(mean(abs_err(:).^2));
                id_rmse     = sqrt(mean(id_abs_err(:).^2));

                total_ber = total_ber + ber;
                total_fec_ber = total_fec_ber + fec_ber;
                total_rmse = total_rmse + rmse;
                valid_count = valid_count + 1;
               
                %RESULTS
                    %CONSOL OUTPUT
                    snr_bb_gain = -10*log10((obj.data_handler.Ndat+obj.data_handler.Npil)/obj.data_handler.N);
                    snr = stf_h.snr+snr_bb_gain;
                    fprintf('| %4d | %3.3f (%3.3f) | %8.5f | %8.5f | %8.5f | %8.4f | %8.4f | %8.2e | %6s |\n', ...
                        folderIdx, stf_h.snr, snr, id_ber, ber, fec_ber, id_rmse, rmse, stf_h.cfo, 'OK');
                    
                    %SAVE RESULTS IN MAT
                    resFile = fullfile(currentDir, 'results.mat');
                    save(resFile, 'ber', 'rmse', 'stf_h');
    
                    %SAVE RESULTS IN CVS
                    csvPath = fullfile(obj.OutputDir, 'statistics.csv');
                    new_file = ~isfile(csvPath);
                    
                    fid = fopen(csvPath, 'a');
                    if fid ~= -1
                        if valid_count == 1 & new_file
                            fprintf(fid, 'FolderID, MOD_POW, SNR, MS_SNR, BER, FEC_BER, ID_BER, RMSE, ID_RMSE,\n');
                        end

                        fprintf(fid, ...
                            '%d,%f,%f,%f,%f,%f,%f,%f,%f\n', ...
                            folderIdx, ...
                            obj.data_handler.Mod_pow, ...
                            obj.chan.SNR, ...
                            snr, ...
                            ber, ...
                            fec_ber, ...
                            id_ber, ...
                            rmse, ...
                            id_rmse ...
                        );

                        fclose(fid);
                    end

                %PLOTS
                if obj.graph_output
                    %DUMP
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
                        plot(abs(ltf_h.h));
                        title("channel intensity profile");
        
                    %SPECTROGRAM
                    set(0, 'CurrentFigure', fig2);
                        clf;
                        spectrogram(rx_waveform, obj.Config.N, [], 'yaxis', 'centered');
                        max_val = max(10*log10(abs(rx_waveform).^2));
                        clim([max_val-50, max_val]);
                        title(sprintf('Frame %d Spectrogram', folderIdx));
                          
                    %IQ    
                    set(0, 'CurrentFigure', fig3);
                        clf;
                        t = tiledlayout(fig3, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
                        
                        ifft_data_plot = ifft_data ./ sqrt(mean(abs(ifft_data.^2), 'all'));
                        
                        nexttile;
                        scatter(real(ifft_data_plot(:)), imag(ifft_data_plot(:)), 3, 'blue', '.');
                        hold on;
                        scatter(real(rx_eqv_data(:)), imag(rx_eqv_data(:)), 3, 'red', '.');
                        scatter(real(rx_eqv_pilots(:)), imag(rx_eqv_pilots(:)), 7, 'green', '.');
                        hold off;
                        
                        xlim([-2, 2]);
                        ylim([-2, 2]);
                        axis("square");
                        grid on;
                        title(sprintf('Constellation (BER: %.1e)', ber));
        
                        id_ifft_data_plot = id_ifft_data ./ sqrt(mean(abs(id_ifft_data.^2), 'all'));
        
                        nexttile;
                        scatter(real(id_ifft_data_plot(:)), imag(id_ifft_data_plot(:)), 3, 'blue', '.');
                        hold on;
                        scatter(real(id_rx_eqv_data(:)), imag(id_rx_eqv_data(:)), 3, 'red', '.');
                        scatter(real(id_rx_eqv_pilots(:)), imag(id_rx_eqv_pilots(:)), 7, 'green', '.');
                        hold off;
                        
                        xlim([-2, 2]);
                        ylim([-2, 2]);
                        axis("square");
                        grid on;
                        title(sprintf('Constellation (id)'));
                    
                    %ABS ERROR
                    set(0, 'CurrentFigure', fig4);
                        clf;
    
                        if isappdata(fig4, 'graphics_linkprop1')
                            rmappdata(fig4, 'graphics_linkprop1'); 
                        end
                        if isappdata(fig4, 'graphics_linkprop2')
                            rmappdata(fig4, 'graphics_linkprop2')
                        end
    
                        t = tiledlayout(fig4, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        
                        ax1 = nexttile;
                        mesh(ax1, abs_err);
                        title(ax1, sprintf('Frame %d RMSE', folderIdx));
                        colormap(ax1, 'jet');    
                        axis(ax1, 'xy');            
                        xlabel(ax1, 'Time / Index');
                        ylabel(ax1, 'Frequency / Range');
                        zlim(ax1, [0, 1]);
                        clim(ax1, [0, 1]);
                        
                        ax2 = nexttile;
                        mesh(ax2, id_abs_err);
                        title(ax2, sprintf('Frame %d RMSE (id)', folderIdx));
                        colormap(ax2, 'jet');    
                        axis(ax2, 'xy');            
                        xlabel(ax2, 'Time / Index');
                        ylabel(ax2, 'Frequency / Range');
                        zlim(ax2, [0, 1]);
                        clim(ax2, [0, 1]);
                        
                        hLink1 = linkprop([ax1, ax2], {'CameraPosition', 'CameraUpVector', 'CameraViewAngle'});
                        hLink2 = linkprop([ax1, ax2], {'XLim', 'YLim', 'ZLim'});
                        
                        setappdata(fig4, 'graphics_linkprop1', hLink1);
                        setappdata(fig4, 'graphics_linkprop2', hLink2);
    
                    %BIT ERROR
                    set(0, 'CurrentFigure', fig5);
                        clf();
                        t = tiledlayout(fig5, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        
                        ax1 = nexttile;
                        imagesc(ax1, err);
                        title(ax1, sprintf('Frame %d BER', folderIdx));
                        colormap(ax1, 'gray');    
                        axis(ax1, 'xy');            
                        xlabel(ax1, 'Time / Index');
                        
                        ax2 = nexttile;
                        imagesc(ax2, fec_err);
                        title(ax2, sprintf('Frame %d FEC BER', folderIdx));
                        colormap(ax2, 'gray');    
                        axis(ax2, 'xy');            
                        xlabel(ax2, 'Time / Index');
                        ylabel(ax2, 'Frequency / Range');
    
                    % SAVE PLOTS
                    plotPath = fullfile(currentDir, 'analysis_plot.png');
                    exportgraphics(fig3, plotPath, 'Resolution', 300);
                end
            end
            
            if valid_count > 0
                fprintf('|%s|\n', repmat('-', 1, 100));
                fprintf('Avg BER: %e | Avg BER(FEC): %e | Avg RMSE: %f\n', total_ber/valid_count, total_fec_ber/valid_count, total_rmse/valid_count);
            end
        end
        
    end
end