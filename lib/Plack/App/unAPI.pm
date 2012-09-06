use strict;
use warnings;
package Plack::App::unAPI;
#ABSTRACT: Serve via unAPI
use v5.10.1;

use parent qw(Plack::Middleware::Negotiate Exporter);

use Plack::Request;
use Carp qw(croak);

our @EXPORT = qw(unAPI wrAPI);

use Log::Contextual::WarnLogger;
use Log::Contextual qw(:log :Dlog), -default_logger
    => Log::Contextual::WarnLogger->new({ env_prefix => 'PLACK_APP_UNAPI' });

## no critic
sub unAPI(@) { __PACKAGE__->new(@_) }
## use critic

sub new {
    my ($class, %formats) = @_;

    my $self = bless {
        formats => { },
        apps    => { },
    }, ref $class || $class;

    foreach my $name (grep { $_ ne '_' } keys %formats) {
        my ($app, $type, %about) = @{$formats{$name}};
        croak "unAPI format required MIME type" unless $type;

        $self->{apps}->{$name} = $app;
        $self->{formats}->{$name} = { type => $type, %about };

        log_trace { "Initialized Plack::App::unAPI with format=$_ for $type" };
    }

    $self->{formats}->{_} = $formats{_};

    $self->prepare_app;
    $self;
}

sub call {
    my ($self, $env) = @_;
    my $req    = Plack::Request->new($env);
    my $format = $req->param('format') // '';
    my $id     = $req->param('id') // '';

    # TODO: here we could first lookup the resource at the server
    # and sent 404 if no known format was specified

    return $self->formats($id)
        if $format ~~ ['','_'];

    my $route = $self->{formats}->{$format};
    if ( !$route || !$self->{apps}->{$format} ) {
        my $res = $self->formats($id);
        $res->[0] = 406; # Not Acceptable
        return $res;
    }

    return $self->formats('')
        if $id eq '' and !($route->{always} // $self->{formats}->{_}->{always});

    log_trace { "Valid unAPI request with format=$format id=$id" };

    my $res = eval {
        $self->{apps}->{$format}->( $env );
    };
    my $error = $@;

    if ( $error ) {
        $error = "Internal crash with format=$format and id=$id: $error";
    } elsif (not is_psgi_response($res)) {
        # we may also check response type...
        $error = "No PSGI response for format=$format and id=$id";
    }

    if ($error) { # TODO: catch only on request
        log_warn { $error };
        return [ 500, [ 'Content-Type' => 'text/plain' ], [ $error ] ];
    }

    $res;
}

# checks whether PSGI conforms to PSGI specification
sub is_psgi_response {
    my $res = shift;
    return (ref($res) and ref($res) eq 'ARRAY' and
        (@$res == 3 or @$res == 2) and
        $res->[0] =~ /^\d+$/ and $res->[0] >= 100 and
        ref $res->[1] and ref $res->[1] eq 'ARRAY');
}

sub formats {
    my ($self, $id, $header) = @_;

    my $status = 300; # Multiple Choices
    my $type   = 'application/xml; charset: utf-8';
    my @xml    = ($header // '<?xml version="1.0" encoding="UTF-8"?>');

    push @xml, $id eq '' ?  '<formats>'
                         : "<formats id=\"" . _xmlescape($id) . "\">";

    while (my ($name, $format) = each %{$self->{formats}}) {
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

    # TODO: error response in corresponding content type

    my $app = sub {
        my $id = Plack::Request->new(shift)->param('id') // '';

        my $obj = $code->( $id ); # look up object

        return defined $obj
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

=head1 SYNOPSIS

Create <app.psgi> like this:

    use Plack::App::unAPI;

    my $app1 = sub { ... };   # PSGI app that serves resource in JSON
    my $app2 = sub { ... };   # PSGI app that serves resource in XML
    my $app3 = sub { ... };   # PSGI app that serves resource in plain text

    unAPI
        json => [ $app1 => 'application/json' ],
        xml  => [ $app2 => 'application/xml' ],
        txt  => [ $app3 => 'text/plain', docs => 'http://example.com' ];

Run for instance by calling C<plackup yourscript.psgi> and retrieve:

    http://localhost:5000/?id=abc&format=json  # calls $app1->($env);
    http://localhost:5000/?id=abc&format=xml   # calls $app2->($env);
    http://localhost:5000/?id=abc&format=txt   # calls $app3->($env);
    http://localhost:5000/                     # returns list of formats
    http://localhost:5000/?format=xml          # returns list of formats
    http://localhost:5000/?id=abc              # returns list of formats

PSGI applications can be created as subclass of L<Plack::Component> or as
simple code reference:

    use Plack::Request;

    # PSGI application that serves resource in JSON

    sub get_resource_as_json {
        my $id = shift;
        ...
        return $json;
    }

    my $app1 = sub {
        my $id   = Plack::Request->new(shift)->param('id') // '';
        my $json = get_resource_as_json( $id );

        return defined $json
            ? [ 200, [ 'Content-Type' => $type ], [ $json ] ]
            : [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
    };

To facilitate applications as above, Plack::App::unAPI exports the function
C<wrAPI> which can be used like this:

    use Plack::App::unAPI;

    unAPI
        json => wrAPI( \&get_resource_as_json  => 'application/json' ),
        xml  => wrAPI( \&get_resource_as_xml   => 'application/xml' ),
        txt  => wrAPI( \&get_resource_as_plain => 'text/plain' );

=head1 DESCRIPTION

Plack::App::unAPI implements an unAPI server as PSGI application. The HTTP
request is routed to different PSGI applications based on the requested format.

A L<PSGI> application is a Perl code reference or an object with a C<call>
method that gets an environment variable and returns an array reference with
defined structure as HTTP response.

L<unAPI|http://unapi.info> is a tiny HTTP API to query discretely identified
resources in different formats.  The basic idea of unAPI is having two HTTP GET
query parameters:

=over 4

=item *

B<id> as resource identifier

=item *

B<format> to select a format

=back

If no (or no supported) format is specified, a list of formats is returned as
XML document.

=method new ( %formats [, _ => { %options } ] )

To create a server object you must provide a list of mappings between format
names and PSGI applications to serve requests for the particular format. Each
application is wrapped in an array reference, followed by its MIME type and
optional information fields about the format. So the general form is:

    format => [ $app => $type, %about ]

The following optional information fields are supported:

=over

=item docs

An URL of a document that describes the format

=item always

By default, the format list with HTTP status code 300 is returned if unless
both, format and id have been supplied. If 'always' is set to true, an empty
identifier will also be routed to the format's application.

=item quality

A number between 0.000 and 1.000 that describes the "source quality" for
content negotiation. The default value is 1.

=item encoding

One or more content encodings, for content negotiation. Typical values are
C<gzip> or C<compress>.

=item charset

The charset for content negotiation (C<undef> by default).

=item language

One or more languages for content negotiation (C<undef> by default).

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

=method variants

Returns a list of content variants to be used in L<HTTP::Negotiate>. The return
value is an array reference of array references, each with seven elements:
format name, source quality (qs), type, encoding, charset, language, and size.
The return value for the example given above would be:

    [
        ['json','1','application/json',undef,undef,undef,0],
        ['xml','1','application/xml',undef,undef,undef,0],
        ['txt','1','text/plain',undef,undef,undef,0]
    ]

=head1 LOGGING AND DEBUGGING

Plack::App::unAPI uses L<Log::Contextual>. To get detailed logging messages set
C<< $ENV{PLACK_APP_UNAPI_TRACE} = 1 >>.

=head1 SEE ALSO

=over

=item

L<Plack::Middleware::Negotiate>

=item

L<http://unapi.info>

=item

Chudnov et al. (2006): I<Introducing unAP>. In: Ariadne, 48,
<http://www.ariadne.ac.uk/issue48/chudnov-et-al/>.

=back

=cut
