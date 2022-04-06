#!/usr/bin/perl
use Data::Dumper;
use strict;

my $module = "STOPMEA";

sub exeCmd{
	my ($cmd) = @_;
	my $subname = "exeCmd";
	print "[$module][$subname] Executing: $cmd\n";
	return `$cmd`;
}
sub exeCmds{
	my @cmds = @_;
	my @outputs;
	foreach (@cmds){
		push (@outputs, exeCmd ($_));
	}
	return @outputs;
}
sub stopAllCaptureProcess{
	my $subname = "exeCmd";
	my $cmd = "sudo ps -ef | grep -E capture|sar|tail";
		
	print "[$module][$subname] stopAllCaptureProcess via $cmd\n";
	my @outputs = exeCmds($cmd);
	foreach (@outputs){
		if($_ =~ /(root|admin)\s+(\d+)/){
			exeCmd("sudo kill $2");
		}
	}
}

sub checkAllResource{
	my $subname = "exeCmd";
	my $cmd = "sudo ls -ltr /var/spool/asterisk/monitor/";
	exeCmd($cmd);
}
checkAllResource();
stopAllCaptureProcess();