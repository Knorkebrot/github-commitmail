#!/usr/bin/perl -w
#
# Note: Github accepts only 60 requests per minute per client
#

use strict;

use JSON;
use Mail::Send;
use LWP::UserAgent;

my $CONF = '/usr/local/etc/github-commitmail.conf';
my $STATE = '/var/tmp/github-commitmail';
my $FROM = '';

die 'No config found: ' . $CONF if (! -f $CONF);

my $ua = LWP::UserAgent->new;
$ua->agent("banane ");
$ua->env_proxy;		# load possible proxies from your env

if (! -e $STATE) {
	open(STATE, '>', $STATE);
	close(STATE);
};
open(STATE, '<', $STATE);
my @statelist = <STATE>;
close(STATE);

my %states;
foreach (@statelist) {
	my ($key, $value) = split(':', $_);
	$value =~ s/\s*$//;
	$states{$key} = $value;
}

open(CONF, '<', $CONF);
foreach (<CONF>) {
	next if ($_ =~ /^\s*$/ || $_ =~ /^#/);	# comments and empty lines
	if ($_ =~ /^from:\s*(.*)$/) {
		$FROM = $1;
		next;
	}
	die "Malformed config line: " . $_ unless ($_ =~ /^([\w\/\-]+):\s*([\w\-@ .]+)$/);
	my @users = split(/\s+/, $2);
	processRepo($1, \@users);
}
close(CONF);

open(STATE, '>', $STATE);
while (my ($repo, $id) = each(%states)) {
	print STATE $repo, ':', $id, "\n";
}
close(STATE);


#
# processRepo()
#
sub processRepo
{
	my $repo = shift;
	my @users = @{ shift() };

	foreach (reverse getCommitlist($repo, $states{$repo}, 1, $ua)) {
		my $commit = decode_json(
			get($ua, 'http://github.com/api/v2/json/commits/show/' . $repo . '/' . $_)
		)->{'commit'};
		my $subject = $repo . ': ' .
			substr($commit->{'id'}, 0, 9);
		my $text = 'Author: ' . ($commit->{'author'}->{'name'} || 'unknown') .
			' <' . ($commit->{'author'}->{'email'} || 'no address') . ">\n";
		$text .= 'Committer: ' . ($commit->{'committer'}->{'name'} || 'unknown') .
			' <' . ($commit->{'committer'}->{'email'} || 'no address') . ">\n";
		$text .= 'Authored date: ' . $commit->{'authored_date'} . "\n";
		$text .= 'Commited date: ' . $commit->{'authored_date'} . "\n";
		$text .= 'Id: ' . $commit->{'id'} . "\n";
		$text .= "\n";

		my %dirs;
		if ($commit->{'added'}) {
			# TODO
			# The API call doesn't deliver a diff for new files. That sucks.
			$text .= "Added:\n";
			foreach (@{$commit->{'added'}}) {
				$text .= '  ' . $_ . "\n";
				getDir(\%dirs, $_);
			}
		}
		if ($commit->{'removed'}) {
			$text .= "Removed:\n";
			foreach (@{$commit->{'removed'}}) {
				$text .= '  ' . $_ . "\n";
				getDir(\%dirs, $_);
			}
		}
		my $diff;
		if ($commit->{'modified'}) {
			$text .= "Modified:\n";
			foreach (@{$commit->{'modified'}}) {
				$text .= '  ' . $_->{'filename'} . "\n";
				$diff .= "\n\nModified: " . $_->{'filename'} . "\n" .
					"===================================================================\n" .
					$_->{'diff'};
				getDir(\%dirs, $_);
			}
		}
		$text .= "Log:\n" . $commit->{'message'} . "\n\n";
		$text .= "URL:\nhttps://github.com" . $commit->{'url'};
		if (length($diff) > 0) {
			$text .= "\n" . $diff;
		}

		my $dirstr = getDirStr(\%dirs);
		$subject .= ' - ' . $dirstr if ($dirstr ne '');

		foreach (@users) {
			my $mail = Mail::Send->new;
			$mail->subject($subject);
			$mail->set('From', 'github@kbct.de');
			$mail->to($_);

			my $fh = $mail->open;
			print $fh $text;
			$fh->close;
		}

		$states{$repo} = $_;
	}
}

#
# getCommitlist()
#
sub getCommitlist
{
	my $repo = shift;
	my $last = shift;
	my $page = shift;
	my $ua = shift;

	my $list = decode_json(
		get($ua, 'http://github.com/api/v2/json/commits/list/' . $repo . '/master?page=' . $page)
	);
	if ($list->{'error'}) {
		die 'Error in JSON: ' . $list->{'error'};
	}
	my @todo;
	foreach (@{$list->{'commits'}}) {
		return @todo if ($last && $_->{'id'} eq $last);
		push(@todo, $_->{'id'});
		return @todo if (!$last);
	}
	return (@todo, getCommitlist($repo, $last, $page + 1, $ua));
}

#
# getDir()
#
sub getDir
{
	my $dirs = shift;
	if (shift =~ /^(.+)\/.+$/ && !$$dirs{$1}) {
		$$dirs{$1} = 1;
	}
}

#
# getDirStr()
#
sub getDirStr
{
	my %dirs = %{ shift() };
	return '' if (!%dirs);
	my $position = -1;
	my $parent = '';
	foreach (keys(%dirs)) {
		if ($position == -1) {
			$position = length($_);
			$parent = $_;
			next;
		}
		my $break = 0;
		# XXX:
		# This is bullshit. I need to split the path
		# at '/' and test for the particular pieces.
		for (my $i = 0; $i < length($parent); $i++) {
			if (substr($parent, $i, 1) ne substr($_, $i, 1)) {
				$position = $i;
				$parent = substr($parent, 0, $position);
				$break = 1;
				last;
			}
			last if ($break);
		}
	}
	my @subdirs;
	foreach (keys(%dirs)) {
		next if ($_ eq $parent);
		push(@subdirs, substr($_, $position, length($_)));
	}
	my $ret = $parent;
	if ($#subdirs > -1) {
		$ret .= ': ' . join(' ', @subdirs);
	}
	return $ret;
}

#
# get()
#
sub get
{
	my $ua = shift;
	my $response = $ua->get(shift);
	if ($response->status_line =~ /^200/ || $response->status_line =~ /^404/) {
		return $response->decoded_content;
	}
	return undef;
}
