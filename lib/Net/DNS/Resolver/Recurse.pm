package Net::DNS::Resolver::Recurse;

#
# $Id: Recurse.pm 1709 2018-09-07 08:03:09Z willem $
#
our $VERSION = (qw$LastChangedRevision: 1709 $)[1];


=head1 NAME

Net::DNS::Resolver::Recurse - DNS recursive resolver


=head1 SYNOPSIS

    use Net::DNS::Resolver::Recurse;

    $resolver = new Net::DNS::Resolver::Recurse();

    $packet = $resolver->query ( 'www.example.com', 'A' );
    $packet = $resolver->search( 'www.example.com', 'A' );
    $packet = $resolver->send  ( 'www.example.com', 'A' );


=head1 DESCRIPTION

This module is a subclass of Net::DNS::Resolver.

=cut


use strict;
use warnings;
use base qw(Net::DNS::Resolver);


=head1 METHODS

This module inherits almost all the methods from Net::DNS::Resolver.
Additional module-specific methods are described below.


=head2 hints

This method specifies a list of the IP addresses of nameservers to
be used to discover the addresses of the root nameservers.

    $resolver->hints(@ip);

If no hints are passed, the priming query is directed to nameservers
drawn from a built-in list of IP addresses.

=cut

my @hints;
my $root = [];

sub hints {
	my $self = shift;

	splice @hints, 0, 0, splice( @hints, int( rand scalar @hints ) );    # cut deck
	return @hints unless scalar @_;
	$root  = [];
	@hints = @_;
}


=head2 query, search, send

The query(), search() and send() methods produce the same result
as their counterparts in Net::DNS::Resolver.

    $packet = $resolver->send( 'www.example.com.', 'A' );

Server-side recursion is suppressed by clearing the recurse flag in
query packets and recursive name resolution is performed explicitly.

The query() and search() methods are inherited from Net::DNS::Resolver
and invoke send() indirectly.

=cut

sub send {
	return &Net::DNS::Resolver::Base::send if ref $_[1];	# send Net::DNS::Packet

	my $self = shift;
	my $res = bless {persistent => {'.' => $root}, %$self}, ref($self);

	my $question = new Net::DNS::Question(@_);
	my $original = pop(@_);					# sneaky extra argument needed
	$original = $question unless ref($original);		# to preserve original request

	my ( $head, @tail ) = $question->{qname}->label;
	my $domain = lc( join( '.', @tail ) || '.' );
	my $nslist = $res->{persistent}->{$domain} ||= [];
	unless ( defined $head ) {
		my $defres = new Net::DNS::Resolver();
		$defres->nameservers( $res->_hints );		# fall back to inbuilt list
		$defres->udppacketsize(1024);			# RFC8109
		my @config = $defres->nameserver( $res->hints );
		return $defres->send(qw(. NS));
	}

	if ( scalar @$nslist ) {
		$self->_diag("using cached nameservers for $domain");
	} else {
		$domain = lc $question->qname if $question->qtype ne 'NULL';
		my $packet = $res->send( $domain, 'NULL', 'IN', $original );
		return unless $packet;

		my @answer = $packet->answer;			# return authoritative answer
		return $packet if $packet->header->aa && grep $_->name eq $original->qname, @answer;

		my @auth = grep $_->type eq 'NS', $packet->answer, $packet->authority;
		my %auth = map { lc $_->nsdname => lc $_->name } @auth;
		my %glue;
		my @glue = grep $_->can('address'), $packet->additional;
		foreach ( grep $auth{lc $_->name}, @glue ) {
			push @{$glue{lc $_->name}}, $_->address;
		}

		my %zone = reverse %auth;
		foreach my $zone ( keys %zone ) {
			my @nsname = grep $auth{$_} eq $zone, keys %auth;
			my @list = map $glue{$_} ? $glue{$_} : $_, @nsname;
			@{$res->{persistent}->{$zone}} = @list;
			return $packet if length($zone) > length($domain);
			$self->_diag("cache nameservers for $zone");
			@$nslist = @list;
		}
	}

	my $query = new Net::DNS::Packet();
	$query->{question} = [$original];
	$res = bless {%$res}, qw(Net::DNS::Resolver) if $nslist eq $root;
	$res->udppacketsize(1024);
	$res->recurse(0);

	splice @$nslist, 0, 0, splice( @$nslist, int( rand scalar @$nslist ) );	   # cut deck

	foreach my $ns (@$nslist) {
		if ( ref $ns ) {
			my @ip = map @$_, grep ref($_), @$nslist;
			$res->nameservers(@ip);			# cached IP list
		} else {
			$self->_diag("find missing glue for $ns");
			my $name = $ns;				# suppress deep recursion by
			$ns = [];				# inserting placeholder in cache
			$ns = [$res->nameservers($name)];	# substitute IP list in situ
		}

		my $reply = $res->send($query);
		next unless $reply;

		$self->_callback($reply);
		return $reply;
	}
}


sub query_dorecursion { &send; }				# uncoverable pod


=head2 callback

This method specifies a code reference to a subroutine,
which is then invoked at each stage of the recursive lookup.

For example to emulate dig's C<+trace> function:

    my $coderef = sub {
	my $packet = shift;

	printf ";; Received %d bytes from %s\n\n",
		$packet->answersize, $packet->answerfrom;
    };

    $resolver->callback($coderef);

The callback subroutine is not called
for queries for missing glue records.

=cut

sub callback {
	my $self = shift;

	( $self->{callback} ) = grep ref($_) eq 'CODE', @_;
}

sub _callback {
	my $callback = shift->{callback};
	$callback->(@_) if $callback;
}

sub recursion_callback { &callback; }				# uncoverable pod


1;

__END__


=head1 ACKNOWLEDGEMENT

This package is an improved and compatible reimplementation of the
Net::DNS::Resolver::Recurse.pm created by Rob Brown in 2002,
whose contribution is gratefully acknowledged.


=head1 COPYRIGHT

Copyright (c)2014 Dick Franks.

Portions Copyright (c)2002 Rob Brown.

All rights reserved.


=head1 LICENSE

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted, provided
that the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation, and that the name of the author not be used in advertising
or publicity pertaining to distribution of the software without specific
prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.


=head1 SEE ALSO

L<Net::DNS::Resolver>

=cut
