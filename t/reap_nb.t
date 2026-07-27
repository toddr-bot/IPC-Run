#!/usr/bin/perl

=pod

=head1 NAME

reap_nb.t - Test suite for IPC::Run->reap_nb() method

=head1 DESCRIPTION

Tests the non-blocking reap method, which attempts to collect child
exit statuses without blocking.  This is the only exported API function
in IPC::Run that previously had zero test coverage.

=cut

use strict;
use warnings;

BEGIN {
    $|  = 1;
    $^W = 1;
    if ( $ENV{PERL_CORE} ) {
        chdir '../lib/IPC/Run' if -d '../lib/IPC/Run';
        unshift @INC, 'lib', '../..';
        $^X = '../../../t/' . $^X;
    }
}

use Test::More;
use IPC::Run qw( harness start );

if ( IPC::Run::Win32_MODE() ) {
    plan skip_all => 'reap_nb tests not supported on Win32';
}

plan tests => 10;

my @perl = ($^X);

# -----------------------------------------------------------------------
# Test 1-2: reap_nb on a running child does not block
# -----------------------------------------------------------------------
{
    my $h = start( [ @perl, '-e', 'sleep 60' ] );

    my $before = time;
    $h->reap_nb;
    my $elapsed = time - $before;

    ok( $elapsed < 5, 'reap_nb returns quickly when child is still running' );
    ok( $h->pumpable, 'harness still pumpable after reap_nb on running child' );

    $h->kill_kill;
    $h->finish;
}

# -----------------------------------------------------------------------
# Test 3-5: reap_nb collects exit status of a finished child
# -----------------------------------------------------------------------
{
    my $out = '';
    my $h = start( [ @perl, '-e', 'print "done\n"' ], '>', \$out );

    # Drain output so the child can exit
    $h->pump while $h->pumpable;

    # Child has exited; reap_nb should collect it
    $h->reap_nb;

    # finish() should complete without hanging since reap_nb pre-reaped
    my $before = time;
    my $ok = $h->finish;
    my $elapsed = time - $before;

    ok( $elapsed < 5, 'finish() completes quickly after reap_nb pre-reaped' );
    ok( $ok,          'finish() returns true (child exited 0)' );
    is( $out, "done\n", 'output was captured correctly' );
}

# -----------------------------------------------------------------------
# Test 6-7: reap_nb is idempotent — safe to call multiple times
# -----------------------------------------------------------------------
{
    my $h = start( [ @perl, '-e', 'exit 0' ] );

    $h->pump while $h->pumpable;

    $h->reap_nb;
    $h->reap_nb;
    $h->reap_nb;

    my $ok = $h->finish;
    ok( $ok, 'finish() succeeds after multiple reap_nb calls' );
    ok( !$h->result, 'result() false (all children exited 0) after reap_nb' );
}

# -----------------------------------------------------------------------
# Test 8-10: reap_nb with non-zero exit code
# -----------------------------------------------------------------------
{
    my $h = start( [ @perl, '-e', 'exit 42' ] );

    $h->pump while $h->pumpable;

    $h->reap_nb;

    my $ok = $h->finish;
    ok( !$ok, 'finish() returns false for non-zero exit' );
    is( $h->result, 42, 'result() reflects non-zero exit after reap_nb' );
    is( $h->full_result, 42 << 8, 'full_result() reflects raw $? after reap_nb' );
}
