package CATS::Formal::Constants;
use strict;
use warnings;

use Exporter qw(import);
BEGIN {   
    our @EXPORT = qw(
        TOKEN_TYPES TOKENS STR_TOKENS FD_TYPES TOKENS_STR RTOKENS
        PRIORS PREF_PRIOR CMP_PRIOR RFD_TYPES WTF
    );
}

my $enum = 0;
use constant {
    TOKEN_TYPES => {
        OPERATOR        => $enum++,
        WORD            => $enum++,
        CONSTANT_FLOAT  => $enum++,
        CONSTANT_STR    => $enum++,
        CONSTANT_INT    => $enum++,
        UNKNOWN         => $enum++,
        EOF             => $enum++,
    },

    TOKENS => {
        INT         => $enum++,
        FLOAT       => $enum++,
        STRING      => $enum++,
        SEQ         => $enum++,
        END         => $enum++,
        NEWLINE     => $enum++,
        NAME        => $enum++,
        CHARS       => $enum++,
        SENTINEL    => $enum++,
        CONSTRAINT  => $enum++,
        NOT         => $enum++,
        PLUS        => $enum++,
        MINUS       => $enum++,
        MUL         => $enum++,
        DIV         => $enum++,
        MOD         => $enum++,
        POW         => $enum++,
        SEMICOLON   => $enum++,
        COMMA       => $enum++,
        DOT         => $enum++,
        LPAREN      => $enum++,
        RPAREN      => $enum++,
        LQBR        => $enum++,
        RQBR        => $enum++,
        LT          => $enum++,
        GT          => $enum++,
        EQ          => $enum++,
        NE          => $enum++,
        LE          => $enum++,
        GE          => $enum++,
        AND         => $enum++,
        OR          => $enum++,
        SHARP       => $enum++,
        EOF         => $enum++,
        UNKNOWN     => $enum++,
    },
};

use constant {
    STR_TOKENS => {
        'int'        => TOKENS->{INT},
        'integer'    => TOKENS->{INT},
        'float'      => TOKENS->{FLOAT},
        'double'     => TOKENS->{FLOAT},
        'string'     => TOKENS->{STRING},
        'str'        => TOKENS->{STRING},
        'end'        => TOKENS->{END},
        'seq'        => TOKENS->{SEQ},
        'sequence'   => TOKENS->{SEQ},
        'assert'     => TOKENS->{CONSTRAINT},
        'constraint' => TOKENS->{CONSTRAINT},
        'sentinel'   => TOKENS->{SENTINEL},
        'newline'    => TOKENS->{NEWLINE},
        'name'       => TOKENS->{NAME},
        'chars'      => TOKENS->{CHARS},
        '#'          => TOKENS->{SHARP},
        ';'          => TOKENS->{SEMICOLON},
        '.'          => TOKENS->{DOT},
        '!'          => TOKENS->{NOT},
        '+'          => TOKENS->{PLUS},
        '-'          => TOKENS->{MINUS},
        '*'          => TOKENS->{MUL},
        '/'          => TOKENS->{DIV},
        '%'          => TOKENS->{MOD},
        '^'          => TOKENS->{POW},
        ','          => TOKENS->{COMMA},
        '('          => TOKENS->{LPAREN},
        ')'          => TOKENS->{RPAREN},
        '['          => TOKENS->{LQBR},
        ']'          => TOKENS->{RQBR},
        '<'          => TOKENS->{LT},
        '>'          => TOKENS->{GT},
        '='          => TOKENS->{EQ},
        '=='         => TOKENS->{EQ},
        '!='         => TOKENS->{NE},
        '<>'         => TOKENS->{NE},
        '<='         => TOKENS->{LE},
        '>='         => TOKENS->{GE},
        '&&'         => TOKENS->{AND},
        '||'         => TOKENS->{OR},
        ''           => TOKENS->{EOF},
    },
    FD_TYPES => {
        INT         => TOKENS->{INT},
        STRING      => TOKENS->{STRING},
        FLOAT       => TOKENS->{FLOAT},
        SEQ         => TOKENS->{SEQ},
        SENTINEL    => TOKENS->{SENTINEL},
        NEWLINE     => TOKENS->{NEWLINE},
        INPUT       => $enum++,
        OUTPUT      => $enum++,
        ROOT        => $enum++
    }
};

my %RTOKENS = reverse %{TOKENS()};

use constant PRIORS => {
    #TOKENS->{DOT}   => 7,
    TOKENS->{NOT}   => 7,
    TOKENS->{POW}   => 6,
    TOKENS->{MUL}   => 5,
    TOKENS->{DIV}   => 5,
    TOKENS->{MOD}   => 5,
    TOKENS->{PLUS}  => 4,
    TOKENS->{MINUS} => 4,
    TOKENS->{LT}    => 3,
    TOKENS->{GT}    => 3,
    TOKENS->{EQ}    => 3,
    TOKENS->{NE}    => 3,
    TOKENS->{LE}    => 3,
    TOKENS->{GE}    => 3,
    TOKENS->{AND}   => 2,
    TOKENS->{OR}    => 1,
};

my %tmp = reverse %{STR_TOKENS()};
use constant TOKENS_STR => \%tmp;

use constant PREF_PRIOR => PRIORS->{TOKENS->{NOT}};

use constant CMP_PRIOR => PRIORS->{TOKENS->{LT}};

my %RFD_TYPES = reverse %{FD_TYPES()};
use constant RFD_TYPES => \%RFD_TYPES;
1;