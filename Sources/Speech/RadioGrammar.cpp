#include "WhisperBridge.h"
#include "grammar-parser.h"
#include <cctype>
#include <sstream>

// A soft word-level prior. The decoder can still emit words outside the vocabulary.
struct RadioGrammar {
    grammar_parser::parse_state parsed;
    std::vector<const whisper_grammar_element *> rules;
};

RadioGrammar *radio_grammar_create(const char *vocabulary) {
    std::istringstream input(vocabulary);
    std::string word;
    std::string grammar = "root ::= \" \"? word ([,.!?]? \" \" word)* [.!?]?\nword ::= ";
    bool first = true;
    while (input >> word) {
        if (word.find_first_not_of("abcdefghijklmnopqrstuvwxyz'") != std::string::npos) continue;
        if (!first) grammar += " | ";
        first = false;
        grammar += '[';
        grammar += word.front();
        grammar += static_cast<char>(std::toupper(static_cast<unsigned char>(word.front())));
        grammar += ']';
        if (word.size() > 1) grammar += "\"" + word.substr(1) + "\"";
    }
    if (first) return nullptr;
    auto *result = new RadioGrammar;
    result->parsed = grammar_parser::parse((grammar + "\n").c_str());
    result->rules = result->parsed.c_rules();
    if (result->rules.empty()) { delete result; return nullptr; }
    return result;
}

void radio_grammar_apply(RadioGrammar *grammar, whisper_full_params *params) {
    if (!grammar) return;
    params->grammar_rules = grammar->rules.data();
    params->n_grammar_rules = grammar->rules.size();
    params->i_start_rule = grammar->parsed.symbol_ids.at("root");
    params->grammar_penalty = 5.0f;
}

void radio_grammar_free(RadioGrammar *grammar) { delete grammar; }
