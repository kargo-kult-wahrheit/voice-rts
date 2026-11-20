#pragma once
#include "whisper.h"

#ifdef __cplusplus
extern "C" {
#endif
typedef struct RadioGrammar RadioGrammar;
RadioGrammar *radio_grammar_create(const char *vocabulary);
void radio_grammar_apply(RadioGrammar *grammar, struct whisper_full_params *params);
void radio_grammar_free(RadioGrammar *grammar);
#ifdef __cplusplus
}
#endif
