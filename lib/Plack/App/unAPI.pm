use strict;
use warnings;
package Plack::App::unAPI;
#ABSTRACT: Serve via unAPI

use 5.010;
use parent qw(Plack::Component Exporter);
use Plack::Request;
use Carp qw(croak);

our @EXPORT = qw(unAPI wrAPI);

## no critic
sub unAPI(@) { __PACKAGE__->new(@_) }
## use critic

sub new {
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self = bless {@_}, $class;

    $self->{'_'} //= { }; # default options

    foreach (grep { $_ ne '_' } keys %$self) {
        my ($app, $type, %about) = @{$self->{$_}};
        croak "unAPI format required MIME type" unless $type;
        $self->{$_} = { app => $app, type => $type, %about };
    }

    $self;
}

sub call {
    my ($self, $env) = @_;
    my $req    = Plack::Request->new($env);
    my $format = $req->param('format') // '';
    my $id     = $req->param('id') // '';

    # here we could first lookup the resource at the server
    # and sent 404 if no known format was specified

    if ($format eq '' or $format eq '_' or $id eq '') {
        return $self->formats($id);
    }

    if ( !$self->{$format} || !$self->{$format}->{app} ) {
        my $res = $self->formats($id);
        $res->[0] = 406; # Not Acceptable
        return $res;
    }

    my $res = eval { $self->{$format}->{app}->( $env ); };
    my $error = $@;

    if ( $error ) {
        $error = "Internal crash with format=$format and id=$id: $@";
    } elsif (not(
        # check whether PSGI conforms to PSGI specification
        ref($res) and ref($res) eq 'ARRAY' and 
        (@$res == 3 or @$res == 2) and
        $res->[0] =~ /^\d+$/ and $res->[0] >= 100 and
        ref $res->[1] and ref $res->[1] eq 'ARRAY'
    )) {
        $error = "No PSGI response for format=$format and id=$id";
    }
    # we may also check response type...

    return [ 500, [ 'Content-Type' => 'text/plain' ], [ $error ] ] if $error;
 
    $res;
}

sub formats {
    my ($self, $id, $header) = @_;

    my $status = 300; # Multiple Choices
    my $type   = 'application/xml; charset: utf-8';
    my @xml    = ($header // '<?xml version="1.0" encoding="UTF-8"?>');

    push @xml, $id eq '' ?  '<formats>' 
                         : "<formats id=\"" . _xmlescape($id) . "\">";

    while (my ($name, $format) = each %$self) {
        next if $name eq '_';
        my $line = "<format name=\"$name\" type=\"".$format->{type}."\"";
        if ( $format->{docs} ) {
            push @xml, "$line docs=\"" . _xmlescape($format->{docs}) . '" />';
        } else {
            push @xml, "$line />"
        }
    }

    push @xml, '</formats>';

    return [ $status, [ 'Content-Type' => $type ], [ join "\n", @xml] ];
}

sub wrAPI {
    my ($code, $type, %about) = @_;

    my $app = sub {
        my $id = Plack::Request->new(shift)->param('id');

        my $obj = $code->( $id ); # look up object

        return $obj
            ? [ 200, [ 'Content-Type' => $type ], [ $obj ] ]
            : [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
    };

    return [ $app => $type, %about ];
}

sub _xmlescape {
    my $xml = shift;
    if ($xml =~ /[\&\<\>"]/) {
        $xml =~ s/\&/\&amp\;/g;
        $xml =~ s/\</\&lt\;/g;
        $xml =~ s/\>/\&gt\;/g;
        $xml =~ s/"/\&quot\;/g;
    }
    return $xml;
}

1;

=head1 DESCRIPTION

This implements an unAPI server as PSGI application. unAPI is a tiny HTTP API
to query discretely identified objects in different formats.  The basic idea of
unAPI is having two HTTP GET query parameters: B<id> to select an object, and
B<format> to select a format. If no (or no supported) format is specified, a
list of formats (in XML) is returned instead. 

This implementation routes the request to different PSGI applications based on
a known format parameter, or sends the format list. A L<PSGI> application is a
Perl code reference or an object with a C<call> method that gets an environment
variable and returns an array reference with defined structure as HTTP
response.

=head1 SYNOPSIS

    use Plack::App::unAPI;

    my $app1 = sub { ... };   # a PSGI application
    my $app2 = sub { ... };   # another PSGI application
    my $app3 = sub { ... };   # another PSGI application

    unAPI
        json => [ $app1 => 'application/javascript' ],
        xml  => [ $app2 => 'application/xml' ],
        txt  => [ $app3 => 'text/plain', docs => 'http://example.com' ];

To run this script you can simply call C<plackup yourscript.psgi>. Then try:

    http://localhost:5000/?id=abc&format=json  # calls $app1->($env);
    http://localhost:5000/?id=abc&format=xml   # calls $app2->($env);
    http://localhost:5000/?id=abc&format=txt   # calls $app3->($env);
    http://localhost:5000/                     # returns list of formats
    http://localhost:5000/?format=xml          # returns list of formats
    http://localhost:5000/?id=abc              # returns list of formats

PSGI applications can be created for instance with L<Plack::Component> or by
starting with the following boilerplate:

    use Plack::Request;
    
    my $app1 = sub { 
        my $id = Plack::Request->new(shift)->param('id');

        my $obj = lookup_object( $id ); # look up object

        return $obj
            ? [ 200, [ 'Content-Type' => $type ], [ $obj ] ]
            : [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
    };

To further facilitate such simple applications, this module exports the
function C<wrAPI> (see below). For instance if your function C<lookup_object>
either returns an XML string or C<undef> when passed an identifier, you
can add it to your unAPI server as:

    xml => wrAPI( \&lookup_object => 'application/xml' );

=method new ( %formats [, _ => { %options } ] )

To create a server object you must provide a list of mappings between format
names and PSGI applications to serve requests for the particular format. Each
application is wrapped in an array reference, followed by its MIME type and
optional information fields about the format. So the general form is: 

    format => [ $app => $type, %about ]

The following information fields are supported:

=over

=item docs

An URL of a document that describes the format

=back 

General options for all formats can be passed with the C<_> field (no format
can have the name C<_>).

By default, the result is checked to be valid PSGI (at least to some degree)
and errors in single applications are catched - in this case a response with
HTTP status code 500 is returned.

=method unAPI ( %formats )

The C<unAPI> keyword as constructor alias is exported by default. To prevent
exporting, include this module via C<use Plack::App::unAPI ();>.

=method wrAPI ( $code, $type, [ %about ] )

This method returns an array reference to be passed to the constructor. The
first argument must be a simple code reference that gets called with C<id> as
only parameter. If its return value is C<undef>, a 404 response is returned.
Otherwise the code reference must return a serialized byte string (NO unicode
characters) that has MIME type C<$type>.

=method formats ( [ $id [, $header ] ] )

Returns a PSGI response with status 300 (Multiple Choices) and an XML document
that lists all formats. The optional header argument has default value
C<< <?xml version="1.0" encoding="UTF-8"?> >>. 

=head1 SEE ALSO

=over

=item

L<http://unapi.info>

=item

Chudnov et al. (2006): I<Introducing unAP>. In: Ariadne, 48,
<http://www.ariadne.ac.uk/issue48/chudnov-et-al/>.

=back

=cut
