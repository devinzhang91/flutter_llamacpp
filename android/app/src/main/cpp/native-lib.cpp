#include <string>
#include <android/log.h>
#include "llama.h"
#include "common/common.h"

#include <vector>

#define ATTRIBUTES extern "C" __attribute__((visibility("default"))) __attribute__((used))
#define LOG_TAG "native-lib"

ATTRIBUTES char* getHello() {
    char* buff = new char[100];
    sprintf(buff, "Hello from C++");
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "getHello: %s, address: %p", buff, buff);
    return buff;
}

/// @brief llama.cpp interface

llama_model * model = nullptr;
llama_context * ctx = nullptr;
const int output_buff_szie = 4 * 1024;
char* output_buff;
gpt_params params;

ATTRIBUTES int llamacpp_init(char* model_path){
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "[%s]: %s", __func__, model_path);
    params.model = std::string(model_path);

    if(ctx){
        __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "[%s]: ctx is not null, free.", __func__);
        llama_free(ctx);
        llama_free_model(model);
        llama_backend_free();
        ctx = nullptr;
        model = nullptr;
        delete [] output_buff;
    }
    // init LLM
    llama_backend_init(params.numa);
    // initialize the model
    llama_model_params model_params = llama_model_default_params();
    model = llama_load_model_from_file(params.model.c_str(), model_params);
    if (model == NULL) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s: error: unable to load model\n" , __func__);
        return -1;
    }
    // initialize the context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.seed  = 1234;
    ctx_params.n_ctx = 2048;
    ctx_params.n_threads = params.n_threads;
    ctx_params.n_threads_batch = params.n_threads_batch == -1 ? params.n_threads : params.n_threads_batch;
    ctx = llama_new_context_with_model(model, ctx_params);
    if (ctx == NULL) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s: error: failed to create the llama_context" , __func__);
        return 1;
    }

    output_buff = new char[output_buff_szie];
    return 0;
}

ATTRIBUTES int llamacpp_generate(char* prompt, int length, char* output, int max_tokens_size = 32, void (*flush_callback)(const char*, int) = nullptr){
    
    std::string eval_str;
    // total length of the sequence including the prompt
    const int n_len = max_tokens_size;
    // tokenize the prompt
    std::vector<llama_token> tokens_list;
    tokens_list = ::llama_tokenize(ctx, prompt, true);
    const int n_ctx    = llama_n_ctx(ctx);
    const int n_kv_req = tokens_list.size() + (n_len - tokens_list.size());

    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "%s: n_len = %d, n_ctx = %d, n_kv_req = %d", __func__, n_len, n_ctx, n_kv_req);
    // make sure the KV cache is big enough to hold all the prompt and generated tokens
    if (n_kv_req > n_ctx) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s: error: n_kv_req > n_ctx, the required KV cache size is not big enough\n", __func__);
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "%s:        either reduce n_parallel or increase n_ctx\n", __func__);
        return -1;
    }
    // print the prompt token-by-token
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "print the prompt token-by-token:%d ", __LINE__);
    for (auto id : tokens_list) {
        __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "%s", llama_token_to_piece(ctx, id).c_str());
    }
    // generate
    // create a llama_batch with size 512
    // we use this object to submit token data for decoding
    llama_batch batch = llama_batch_init(512, 0);
    // evaluate the initial prompt
    batch.n_tokens = tokens_list.size();
    for (int32_t i = 0; i < batch.n_tokens; i++) {
        batch.token[i]  = tokens_list[i];
        batch.pos[i]    = i;
        batch.seq_id[i] = 0;
        batch.logits[i] = false;
    }
    // llama_decode will output logits only for the last token of the prompt
    batch.logits[batch.n_tokens - 1] = true;

    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "llama_decode:%d ", __LINE__);
    if (llama_decode(ctx, batch) != 0) {
        fprintf(stderr, "%s : failed to eval, return code %d\n", __func__, 1);
        llama_batch_free(batch);
        return -2;
    }
    int n_cur    = batch.n_tokens;
    int n_decode = 0;
    const auto t_main_start = ggml_time_us();
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "t_main_start = %d", t_main_start);

    while (n_cur <= n_len) {
        // sample the next token
        {
            __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "llama_n_vocab:%d ", __LINE__);
            auto   n_vocab = llama_n_vocab(model);
            __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "llama_get_logits_ith:%d ", __LINE__);
            auto * logits  = llama_get_logits_ith(ctx, batch.n_tokens - 1);

            std::vector<llama_token_data> candidates;
            candidates.reserve(n_vocab);

            for (llama_token token_id = 0; token_id < n_vocab; token_id++) {
                candidates.emplace_back(llama_token_data{ token_id, logits[token_id], 0.0f });
            }

            llama_token_data_array candidates_p = { candidates.data(), candidates.size(), false };

            // sample the most likely token
            __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "llama_sample_token_greedy:%d ", __LINE__);
            const llama_token new_token_id = llama_sample_token_greedy(ctx, &candidates_p);

            // is it an end of stream?
            if (new_token_id == llama_token_eos(ctx) || n_cur == n_len) {
                __android_log_print(ANDROID_LOG_INFO, LOG_TAG, " [eos]\n");
                break;
            }

            const auto t_main_cur = ggml_time_us();
            __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "speed: %.2f t/s\n", n_decode / ((t_main_cur - t_main_start) / 1000000.0f));
            __android_log_print(ANDROID_LOG_INFO, LOG_TAG, " %d:: %s ", new_token_id, llama_token_to_piece(ctx, new_token_id).c_str());
            eval_str += llama_token_to_piece(ctx, new_token_id);
            std::replace(eval_str.begin(), eval_str.end(), '\n', ' ');// trim
            // flush
            flush_callback(eval_str.c_str(), eval_str.length());

            // prepare the next batch
            batch.n_tokens = 0;

            // push this new token for next evaluation
            batch.token [batch.n_tokens] = new_token_id;
            batch.pos   [batch.n_tokens] = n_cur;
            batch.seq_id[batch.n_tokens] = 0;
            batch.logits[batch.n_tokens] = true;

            batch.n_tokens += 1;

            n_decode += 1;
            __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "n_decode=%d, n_cur=%d, n_len=%d", n_decode, n_cur, n_len);
        }

        n_cur += 1;

        // evaluate the current batch with the transformer model
        if (llama_decode(ctx, batch)) {
            fprintf(stderr, "%s : failed to eval, return code %d\n", __func__, 1);
            llama_batch_free(batch);
            return -2;
        }
    }
    const auto t_main_end = ggml_time_us();
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "%s: decoded %d tokens in %.2f s, speed: %.2f t/s\n",
            __func__, n_decode, (t_main_end - t_main_start) / 1000000.0f, n_decode / ((t_main_end - t_main_start) / 1000000.0f));

    // copy eval_str to output
    strcpy(output, eval_str.c_str());
    __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "[%s] output: %s", __func__, output);

    llama_batch_free(batch);
    return eval_str.length();
}


ATTRIBUTES int llamacpp_deinit(){
    if(ctx){
        llama_free(ctx);
        llama_free_model(model);
        llama_backend_free();
        ctx = nullptr;
        model = nullptr;
        delete [] output_buff;
        __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "[%s]: done", __func__);
        return 0;
    } else {
        __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, "[%s]: ctx is null", __func__);
        return -1;
    }

}

