#include "WhisperBridge.h"
#include "grammar-parser.h"

// Used only to re-decode an acoustically similar but unrecognized field order.
static const char *grammar = R"GRAMMAR(root ::= " "? (group (", " | " "))? (move | attack | hold | retreat) [.!?]?
group ::= [Aa]"rchers" | [Ii]"nfantry" | [Cc]"avalry" | [Ll]"ight " [Cc]"avalry" | [Bb]"owmen" | [Rr]"iders" | [Ff]"ootmen" | [Aa]"ll units" | [Ee]"veryone" | [Aa]"ll troops"
move ::= ([Mm]"ove" | [Gg]"o" | [Aa]"dvance" | [Hh]"ead" | [Mm]"arch" | [Rr]"ide" | [Rr]"ally") (" to" | " towards" | " across" | " for")? " " location
attack ::= ([Aa]"ttack" | [Ee]"ngage" | [Cc]"harge" | [Ss]"hoot" | [Ff]"ocus fire" | [Ff]"ire" | [Ff]"lank") (" at" | " on" | " the")? (" " (opponent | location))?
hold ::= ([Hh]"old" | [Gg]"uard" | [Dd]"efend" | [Ww]"ait" | [Ss]"tay") (" here" | " still" | " put" | " position" | " the line" | " your ground" | (" at" | " near")? " " location)? | [Ss]"tand your ground" | [Hh]"alt" | [Ss]"top"
retreat ::= ([Rr]"etreat" | [Ff]"all back" | [Pp]"ull back" | [Ww]"ithdraw" | [Rr]"egroup" | [Rr]"eturn") (" to" | " at")? (" " location)?
opponent ::= ("the ")? ([Ee]"nemy" | [Hh]"ostile" | [Rr]"ed") (" " group)? | "their " group | group
location ::= ("the " | "our ")? place
place ::= [Nn]"orth " [Bb]"ridge" | [Ss]"outh " [Bb]"ridge" | [Nn]"orthern bridge" | [Ss]"outhern bridge" | [Pp]"ine " [Gg]"rove" | [Ss]"late " [Rr]"idge" | [Ww]"est " [Cc]"amp" | [Ee]"ast " [Cc]"amp" | [Ee]"nemy camp" | [Ww]"est " [Bb]"ank" | [Cc]"amp" | [Bb]"ase" | [Hh]"ome" | [Mm]"arker" | [Pp]"in" | [Nn]"orth" | [Ss]"outh" | [Tt]"here"
)GRAMMAR";

void radio_grammar_apply(whisper_full_params *params) {
    static const auto parsed = grammar_parser::parse(grammar);
    static auto rules = parsed.c_rules();
    if (rules.empty()) return;
    params->grammar_rules = rules.data();
    params->n_grammar_rules = rules.size();
    params->i_start_rule = parsed.symbol_ids.at("root");
    params->grammar_penalty = 100;
}
