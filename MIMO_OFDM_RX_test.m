%% Correlate for LTS
LTS_CORR_THRESH = .8;
DO_APPLY_CFO_CORRECTION = 1;
DO_APPLY_SFO_CORRECTION = 1;
DO_APPLY_PHASE_ERR_CORRECTION = 1;

% For simplicity, we'll only use RFA for LTS correlation and peak
% discovery. A straightforward addition would be to repeat this process for
% RFB and combine the results for detection diversity.

% Complex cross correlation of Rx waveform with time-domain LTS
lts_corr = abs(conv(conj(fliplr(lts_t)), sign(raw_rx_dec_A)));

% Skip early and late samples - avoids occasional false positives from pre-AGC samples
lts_corr = lts_corr(32 : end - 32);

% Find all correlation peaks
lts_peaks = find(lts_corr > LTS_CORR_THRESH * max(lts_corr));

% Select best candidate correlation peak as LTS-payload boundary
% In this MIMO example, we actually have 3 LTS symbols sent in a row.
% The first two are sent by RFA on the TX node and the last one was sent
% by RFB. We will actually look for the separation between the first and the
% last for synchronizing our starting index.

[LTS1, LTS2] = meshgrid(lts_peaks,lts_peaks);
[lts_last_peak_index,y] = find(LTS2-LTS1 == length(lts_t));

% Stop if no valid correlation peak was found
if(isempty(lts_last_peak_index))
    fprintf('No LTS Correlation Peaks Found!\n');
    return;
end

% Set the sample indices of the payload symbols and preamble
% The "+32" here corresponds to the 32-sample cyclic prefix on the preamble LTS
% The "+192" corresponds to the length of the extra training symbols for MIMO channel estimation
mimo_training_ind = lts_peaks(max(lts_last_peak_index)) + 32;
payload_ind = mimo_training_ind + 192;

% Subtract of 2 full LTS sequences and one cyclic prefixes
% The "-160" corresponds to the length of the preamble LTS (2.5 copies of 64-sample LTS)
lts_ind = mimo_training_ind-160;

if(DO_APPLY_CFO_CORRECTION)
    %Extract LTS (not yet CFO corrected)
    rx_lts = raw_rx_dec_A(lts_ind : lts_ind+159); %Extract the first two LTS for CFO
    rx_lts1 = rx_lts(-64 + [97:160]);
    rx_lts2 = rx_lts( [97:160]);

    %Calculate coarse CFO est
    rx_cfo_est_lts = mean(unwrap(angle(rx_lts2 .* conj(rx_lts1))));
    rx_cfo_est_lts = rx_cfo_est_lts/(2*pi*64);
else
    rx_cfo_est_lts = 0;
end

% Apply CFO correction to raw Rx waveforms
rx_cfo_corr_t = exp(-1i*2*pi*rx_cfo_est_lts*[0:length(raw_rx_dec_A)-1]);
rx_dec_cfo_corr_A = raw_rx_dec_A .* rx_cfo_corr_t;
rx_dec_cfo_corr_B = raw_rx_dec_B .* rx_cfo_corr_t;


% MIMO Channel Estimatation
lts_ind_TXA_start = mimo_training_ind + 32 ;
lts_ind_TXA_end = lts_ind_TXA_start + 64 - 1;

lts_ind_TXB_start = mimo_training_ind + 32 + 64 + 32 ;
lts_ind_TXB_end = lts_ind_TXB_start + 64 - 1;

rx_lts_AA = rx_dec_cfo_corr_A(lts_ind_TXA_start : lts_ind_TXA_end);
rx_lts_BA = rx_dec_cfo_corr_A(lts_ind_TXB_start : lts_ind_TXB_end);

rx_lts_AB = rx_dec_cfo_corr_B(lts_ind_TXA_start : lts_ind_TXA_end);
rx_lts_BB = rx_dec_cfo_corr_B(lts_ind_TXB_start : lts_ind_TXB_end);

rx_lts_AA_f = fft(rx_lts_AA);
rx_lts_BA_f = fft(rx_lts_BA);

rx_lts_AB_f = fft(rx_lts_AB);
rx_lts_BB_f = fft(rx_lts_BB);

%% Perform Channel estimation 
disp(rx_lts_AA_f);
H_AA = conj(lts_f) .* rx_lts_AA_f ./ (abs(lts_f) .^ 2);
H_AB = conj(lts_f) .* rx_lts_AB_f ./ (abs(lts_f) .^ 2);
H_BA = conj(lts_f) .* rx_lts_BA_f ./ (abs(lts_f) .^ 2);
H_BB = conj(lts_f) .* rx_lts_BB_f ./ (abs(lts_f) .^ 2);

figure;
stem(abs(H_AA));
%

%% Rx payload processing, Perform combining for 1X4 and 2X2 separately  
rx_dec_cfo_corr_A ;
rx_dec_cfo_corr_B ;

% Extract the payload samples (integral number of OFDM symbols following preamble)
payload_mat_A = zeros(N_SC + N_CB, N_OFDM_SYMS);
payload_mat_B = zeros(N_SC + N_CB, N_OFDM_SYMS);

% Remove the cyclic prefix
payload_mat_noCP_A = payload_mat_A(CP_LEN+[1:N_SC], :);
payload_mat_noCP_B = payload_mat_B(CP_LEN+[1:N_SC], :);

% Take the FFT
syms_f_mat_A = fft(payload_mat_noCP_A, N_SC, 1);
syms_f_mat_B = fft(payload_mat_noCP_B, N_SC, 1);


%*This is optional -- SFO correction*

% Equalize pilots
% Because we only used Tx RFA to send pilots, we can do SISO equalization
% here. This is zero-forcing (just divide by chan estimates)
syms_eq_mat_pilots = syms_f_mat_A ./ repmat(rx_H_est_AA.', 1, N_OFDM_SYMS);

if DO_APPLY_SFO_CORRECTION
    % SFO manifests as a frequency-dependent phase whose slope increases
    % over time as the Tx and Rx sample streams drift apart from one
    % another. To correct for this effect, we calculate this phase slope at
    % each OFDM symbol using the pilot tones and use this slope to
    % interpolate a phase correction for each data-bearing subcarrier.

	% Extract the pilot tones and "equalize" them by their nominal Tx values
 
	% Calculate the phases of every Rx pilot tone
 

	% Calculate the SFO correction phases for each OFDM symbol

    % Apply the pilot phase correction per symbol

else
	% Define an empty SFO correction matrix (used by plotting code below)
    pilot_phase_sfo_corr = zeros(N_SC, N_OFDM_SYMS);
end

%*This is optional* 
% Extract the pilots and calculate per-symbol phase error
if DO_APPLY_PHASE_ERR_CORRECTION
    pilots_f_mat = syms_eq_mat_pilots(SC_IND_PILOTS, :);
    pilot_phase_err = angle(mean(pilots_f_mat.*pilots_mat_A));
else
	% Define an empty phase correction vector (used by plotting code below)
    pilot_phase_err = zeros(1, N_OFDM_SYMS);
end
pilot_phase_corr = repmat(exp(-1i*pilot_phase_err), N_SC, 1);

% Apply pilot phase correction to both received streams
syms_f_mat_pc_A = syms_f_mat_A .* pilot_phase_corr;
syms_f_mat_pc_B = syms_f_mat_B .* pilot_phase_corr;

% Perform combining for MIMO 1X4 and 2X2 
% you need to apply the MIMO equalization to each subcarrier separately and then perform combining

payload_syms_mat_A = syms_eq_mat_A(SC_IND_DATA, :);
payload_syms_mat_B = syms_eq_mat_B(SC_IND_DATA, :);

%% perform demodulate or demapping post combined symbols 


% plot the demodulated output rx_syms_case_1 and rx_syms_case_2
figure(4);
scatter(real(rx_syms_case_1), imag(rx_syms_case_1),'filled');
title(' Signal Space of received bits');
xlabel('I'); ylabel('Q');

figure(5);
scatter(real(rx_syms_case_2), imag(rx_syms_case_2),'filled');
title(' Signal Space of received bits');
xlabel('I'); ylabel('Q');


% FEC decoder for the rx_syms_case_1 and rx_syms_case_2

Demap_out_case_1 = demapper(rx_syms_case_1,MOD_ORDER,1);
Demap_out_case_2 = demapper(rx_syms_case_2,MOD_ORDER,1);

% viterbi decoder
rx_data_final_1= vitdec(Demap_out_case_1,trel,7,'trunc','hard');
rx_data_final_2 = vitdec(Demap_out_case_2,trel,7,'trunc','hard');

% rx_data is the final output corresponding to tx_data, which can be used
% to calculate BER

[number,ber] = biterr(tx_data_a,rx_data_final_1);
[number,ber] = biterr(tx_data_b,rx_data_final_2);
