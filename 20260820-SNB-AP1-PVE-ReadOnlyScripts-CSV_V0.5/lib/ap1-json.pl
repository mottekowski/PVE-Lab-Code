#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);

sub slurp {
    my ($file)=@_;
    open my $fh, '<', $file or die "open $file: $!";
    local $/; my $txt=<$fh>; close $fh;
    return decode_json($txt);
}
sub path_get {
    my ($data,$path)=@_;
    return $data if !defined($path) || $path eq '' || $path eq '.';
    my $cur=$data;
    for my $p (split /\./,$path) {
        return undef if ref($cur) ne 'HASH' || !exists $cur->{$p};
        $cur=$cur->{$p};
    }
    return $cur;
}
sub valstr {
    my ($v)=@_;
    return '' if !defined $v;
    if (!ref($v)) { return $v ? "$v" : ($v eq '0' ? '0' : "$v"); }
    return encode_json($v);
}
sub flatten {
    my ($v,$prefix)=@_;
    if (!ref($v)) {
        print "$prefix\t",valstr($v),"\n";
    } elsif (ref($v) eq 'HASH') {
        for my $k (sort keys %$v) {
            my $p = $prefix eq '' ? $k : "$prefix/$k";
            flatten($v->{$k},$p);
        }
    } elsif (ref($v) eq 'ARRAY') {
        if (!grep { ref($_) } @$v) {
            print "$prefix\t", join(',', map { valstr($_) } @$v), "\n";
        } else {
            for (my $i=0;$i<@$v;$i++) {
                my $p = $prefix eq '' ? "[$i]" : "$prefix/[$i]";
                flatten($v->[$i],$p);
            }
        }
    }
}

my ($mode,$file,@args)=@ARGV;
die "usage: ap1-json.pl <object|array|flatten> FILE ...\n" if !$mode || !$file;
my $data=slurp($file);
if ($mode eq 'object') {
    for my $path (@args) {
        my $v=path_get($data,$path);
        next if !defined $v;
        print "$path\t",valstr($v),"\n";
    }
} elsif ($mode eq 'array') {
    my ($path,$keyfield,@fields)=@args;
    my $arr=path_get($data,$path);
    die "path is not array: $path\n" if ref($arr) ne 'ARRAY';
    for (my $i=0;$i<@$arr;$i++) {
        my $obj=$arr->[$i];
        if (ref($obj) ne 'HASH') {
            print "#$i\tvalue\t",valstr($obj),"\n";
            next;
        }
        my $key=path_get($obj,$keyfield);
        $key="#$i" if !defined($key) || ref($key);
        for my $field (@fields) {
            my $v=path_get($obj,$field);
            next if !defined $v;
            print valstr($key),"\t$field\t",valstr($v),"\n";
        }
    }
} elsif ($mode eq 'flatten') {
    my $path=$args[0] // '.';
    my $v=path_get($data,$path);
    die "path not found: $path\n" if !defined $v;
    flatten($v,'');
} else {
    die "unknown mode: $mode\n";
}
