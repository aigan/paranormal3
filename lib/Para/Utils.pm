#  $Id$  -*-perl-*-
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
#   Copyright (C) 2004 Jonas Liljegren.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
#=====================================================================

=head1 NAME

Para::Utils - Utility functions for paranormal.se

=cut


BEGIN
{
    our $VERSION  = sprintf("%d.%02d", q$Revision$ =~ /(\d+)\.(\d+)/);
    print "Loading ".__PACKAGE__." $VERSION\n";
}

use Para::Frame::Reload;

use base qw( Exporter );
BEGIN
{
    our @EXPORT_OK = qw( cache_update trim_text );

}

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
