package MojoMojo::Schema::Page;

# Created by DBIx::Class::Schema::Loader v0.03003 @ 2006-06-18 12:23:29

use strict;
use warnings;

use base qw/Class::Accessor::Fast DBIx::Class/;

__PACKAGE__->mk_accessors(qw/path/);

__PACKAGE__->load_components("ResultSetManager","PK::Auto", "Core");
__PACKAGE__->table("page");
__PACKAGE__->add_columns(
  "id",
  "version",
  "parent",
  "name",
  "name_orig",
  "depth",
  "lft",
  "rgt",
  "content_version",
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->has_many(
  "wantedpages",
  "WantedPage",
  { "foreign.from_page" => "self.id" },
);
__PACKAGE__->belongs_to("parent", "Page", { id => "parent" });
__PACKAGE__->has_many("children", "Page", { "foreign.parent" => "self.id" });
__PACKAGE__->belongs_to(
  "content",
  "Content",
  { page => "id", version => "content_version" },
);
__PACKAGE__->belongs_to(
  "page_version",
  "PageVersion",
  { page => "id", version => "version" },
);
__PACKAGE__->has_many("tags", "Tag", { "foreign.page" => "self.id" });
__PACKAGE__->has_many(
  "links_from",
  "Link",
  { "foreign.from_page" => "self.id" },
);
__PACKAGE__->has_many("links_to", "Link", { "foreign.to_page" => "self.id" });
__PACKAGE__->has_many(
  "roleprivileges",
  "RolePrivilege",
  { "foreign.page" => "self.id" },
);
__PACKAGE__->has_many("attachments", "Attachment", { "foreign.page" => "self.id" });
__PACKAGE__->has_many("comments", "Comment", { "foreign.page" => "self.id" });
__PACKAGE__->has_many("journals", "Journal", { "foreign.pageid" => "self.id" });

sub path_pages :ResultSet {
    my ( $self, $path, $id ) = @_;

    # avoid recursive path resolution, if possible:
    my @path_pages;
    if ($path eq '/') {
        @path_pages = $self->search({ lft => 1 });
        $path_pages[0]->path( '/' );
    }
    elsif ($id) {
        # this only works if depth is at least 1
        @path_pages = $self->path_pages_by_id( $id );
    }
    return (\@path_pages, []) if (@path_pages > 0);

    my @proto_pages = $self->parse_path($path);

    my $depth      = @proto_pages - 1;          # depth starts at 0
    ## FIXME: Continue porting here

    my @depths;
    for my $proto ( @proto_pages )  {
	push @depths, -and => [ depth =>  $proto->{depth},
	                        name  =>  $proto->{name}];

    }
    my @pages = $self->search( -or => [ @depths ] ); 

    my $query_name = "get_path_depth_$depth";

    unless ( $self->can($query_name) ) {
        my $where = join ' OR ',
          ('( depth = ? AND name = ? )') x ( $depth + 1 );
        $self->add_constructor( $query_name => $where );
    }

    # store query results by depth:
    my @bind = map { $_->{depth}, $_->{name} } @proto_pages;
    my @query_pages;
    for ( $self->$query_name(@bind) ) {
        $query_pages[ $_->depth ] ||= [];
        push @{ $query_pages[ $_->depth ] }, $_;
    }

    # END OF PORTING BLOCK

    my $resolved = $self->resolve_path(
        path_pages    => \@path_pages,
        proto_pages   => \@proto_pages,
        query_pages   => \@query_pages,
        current_depth => 0,
        final_depth   => $depth,
    );

    # If there are any proto pages, put the original
    # page names back into the paths, so they will
    # be preserved upon page creation:
    if (@proto_pages)
    {
	my $proto_path = $path_pages[ @path_pages - 1 ]->{path};
	for (@proto_pages) {
	    ($proto_path =~ /\/$/) || ($proto_path .= '/');
             $proto_path .= $_->{name_orig};
	    $_->{path} = $proto_path;
	}
    }
    return ( \@path_pages, \@proto_pages );

} # end sub get_path


sub path_pages_by_id : ResultSet {
    my ($self,$id)=@_;
    return $self->search({
	'start_page.lft' => 1,
	'end_page.id' => $id,
	'me.lft'       => { 'BETWEEN', 'start_page.lft', 'start_page.rgt' },
	'end_page.lft' => { 'BETWEEN', 'me.lft','me.rgt' },
    },
    {
	from=>\" page AS start_page, page AS me, page AS end_page ",
	order_by => 'me.lft'
    });
}

sub parse_path : ResultSet {
    my ( $self, $path ) = @_;

    # Remove leading and trailing slashes to make
    # split happy. We'll add the root (/) back later...
    $path =~ s/^[\/]+//;
    $path =~ s/[\/]+$//;

    my @proto_pages = map { { name_orig => $_ } } ( split /\/+/, $path );
    if ( @proto_pages == 0 && $path =~ /\S/ ) {
        @proto_pages = ($path);
    }

    my $depth     = 1;
    my $page_path = '';
    for (@proto_pages) {
        ( $_->{name_orig}, $_->{name} ) =
          $self->normalize_name( $_->{name_orig} );
        $page_path .= '/' . $_->{name};
        $_->{path}  = $page_path;
        $_->{depth} = $depth;
        $depth++;
    }
    # assume that all paths are absolute:
    unshift @proto_pages,
      { name => '/', name_orig => '/', path => '/', depth => 0 };

    return @proto_pages;

} # end sub parse_path

sub normalize_name : ResultSet {
    my ( $self, $name_orig ) = @_;

    $name_orig =~ s/^\s+//;
    $name_orig =~ s/\s+$//;
    $name_orig =~ s/\s+/ /g;

    my $name = $name_orig;
    $name =~ s/\s+/_/g;
    $name = lc($name);
    return ( $name_orig, $name );
}

1;
