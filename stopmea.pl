#!/usr/bin/perl
use Data::Dumper;
use strict;
my @output = `sudo ps -ef | grep -E capture`;
foreach (@output){
    if($_ =~ /(root|admin)\s+(\d+)/){
       `sudo kill $2`;
        print "sudo kill $2\n";
    }
}