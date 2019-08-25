#!/bin/bash

python3_cmd=python3
export DATA_DIR=/home/jiazhi/Dataset/common-voice_zh-TW_43h_2019-06-12

. ./path.sh || exit 1
. ./cmd.sh || exit 1

nj=4
lm_order=1

. utils/parse_options.sh || exit 1
[[ $# -ge 1 ]] && { echo "Wrong arguments!"; exit 1; }


# Removing previously created data (from last run.sh execution)
rm -rf data exp mfcc   


echo
echo "===== PREPARING REQUIRED DATA ====="
echo

mkdir data data/train data/test data/local data/local/dict
$python3_cmd scripts/prepare_data.py

echo
echo "===== PREPARING ACOUSTIC DATA ====="
echo

# Making spk2utt files
utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt
utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt

echo
echo "===== FEATURES EXTRACTION ====="
echo

# Making feats.scp files
mfccdir=mfcc
# Uncomment and modify arguments in scripts below if you have any problems with data sorting
# utils/validate_data_dir.sh data/train     # script for checking prepared data - here: for data/train directory
# utils/validate_data_dir.sh data/test
# utils/fix_data_dir.sh data/train          # tool for data proper sorting if needed - here: for data/train directory
# utils/fix_data_dir.sh data/test

steps/make_mfcc.sh --nj $nj --cmd "$train_cmd" data/train \
                        exp/make_mfcc/train $mfccdir
steps/make_mfcc.sh --nj $nj --cmd "$train_cmd" data/test \
                        exp/make_mfcc/test $mfccdir

# Making cmvn.scp files
steps/compute_cmvn_stats.sh data/train exp/make_mfcc/train $mfccdir
steps/compute_cmvn_stats.sh data/test exp/make_mfcc/test $mfccdir

echo
echo "===== PREPARING LANGUAGE DATA ====="
echo
# Preparing language data
utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang data/lang

echo
echo "===== LANGUAGE MODEL CREATION ====="
echo "===== MAKING lm.arpa ====="
echo

loc=`which ngram-count`;
if [ -z $loc ]; then
    if uname -a | grep 64 >/dev/null; then
        sdir=$KALDI_ROOT/tools/srilm/bin/i686-m64
    else
        sdir=$KALDI_ROOT/tools/srilm/bin/i686
    fi
    if [ -f $sdir/ngram-count ]; then
        echo "Using SRILM language modelling tool from $sdir"
        export PATH=$PATH:$sdir
    else
        echo "SRILM toolkit is probably not installed. Instructions: tools/install_srilm.sh"
        exit 1
    fi
fi

local=data/local
mkdir $local/tmp
ngram-count -order $lm_order -write-vocab $local/tmp/vocab-full.txt \
            -wbdiscount -text $local/corpus.txt -lm $local/tmp/lm.arpa

echo
echo "===== MAKING G.fst ====="
echo

lang=data/lang
arpa2fst --disambig-symbol=#0 --read-symbol-table=$lang/words.txt \
                          $local/tmp/lm.arpa $lang/G.fst