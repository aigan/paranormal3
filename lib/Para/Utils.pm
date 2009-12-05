# -*-cperl-*-
package Para::Utils;
#=====================================================================
#
# DESCRIPTION
#   Paranormal.se Utils class
#
# AUTHOR
#   Jonas Liljegren   <jonas@paranormal.se>
#
# COPYRIGHT
#   Copyright (C) 2004-2009 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Utils - Utility functions for paranormal.se

=cut

use strict;
use warnings;
use vars qw( @ISA @EXPORT_OK );

use Para::Frame::Reload;

use Exporter 'import';
our @EXPORT_OK = qw( cache_update trim_text );



sub cache_update
{
    ### TODO: Fix real caching
    $Para::Cache::Changed = time;
}

sub trim_text
{
    my $ref = shift;
    return unless defined $ref;
    $$ref =~ s/\r\n/\n/g;      # Convert to unix LF
    $$ref =~ s/^([ \t]*\n)+//; # Do not trim spacec on first row with text
    $$ref =~ s/\s+$/\n/;       # Leave last whitespace
}

1;
