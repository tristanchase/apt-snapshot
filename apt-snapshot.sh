#! /bin/sh

# be root
test $( id -u )  -eq 0 || exec sudo $0 "$@"

APT_SNAPSHOT_DIR=${APT_SNAPSHOT_DIR-/var/cache/apt/snapshots}
TMPDIR=${TMPDIR-/tmp}

trap 'rm -f "${TMPDIR}/$$" "${TMPDIR}/$$.cur";' INT TERM QUIT HUP EXIT

set -e

id="`basename $0`"

create_exact () {
  dpkg --get-selections                                         |       \
  perl -lane 'print $F[0] if $F[1] eq "install"'                |       \
  xargs dpkg -s                                                 |       \
  perl -e 'BEGIN { $/="Package: "; };'                                  \
       -ne 'chomp;
            m/^([\w\+\-\.]+)/ or next; $p = $1;
            m/Version:\s*([\w\.\+\-:~]+)/ or next; $v = $1;
            print "$p\t$v\n";'                                          \
  > "$1"
}


create () {
  mkdir -p "${APT_SNAPSHOT_DIR}"
  create_exact "${APT_SNAPSHOT_DIR}/$1"
}

fetch_snapshot () {
  case "$1" in
    *:*)
      host=${1%:*}
      file=${1##*:}

      scp "${host}:${APT_SNAPSHOT_DIR}/$file" "$2"
      ;;
    /*|./*)
      test -f "$1" && cp "$1" "$2"
      ;;
    ?*)
      cp "${APT_SNAPSHOT_DIR}/$1" "$2"
      ;;
    *)
      echo "not a snapshot: $1"
      exit 1
      ;;
  esac
}

fetch () {
  test -z "$1" && {
      echo "error: fetch: takes an argument (hint: try '$id list')" 1>&2
      exit 1;
  }

  fetch_snapshot "$1" "./"
}

restore () {
  local cur="${TMPDIR}/$$.cur"
  local target="${TMPDIR}/$$"

  test -z "$1" && {
      echo "error: restore: takes an argument (hint: try '$id list')" 1>&2
      exit 1;
  }
  fetch_snapshot "$1" "$target"

  create_exact "$cur"

  shift

  apt-get "$@" install `
  perl -MIO::File -e 'my $fh = new IO::File ($ARGV[0], "r") or die;
                      while (<$fh>)
                        {
                          my ($k, $v) = split /\t/, $_, 2;
                          $want{$k} = $v;
                        }
                      my $targetfh = new IO::File ($ARGV[1], "r") or die;
                      while (<$targetfh>)
                        {
                          my ($k, $curv) = split /\t/, $_, 2;
                          if (exists $want{$k} && $want{$k} ne $curv)
                            {
                              my $v = $want{$k};
                              print "$k=$v ";
                            }
                          elsif (! exists $want{$k})
                            {
                              print "$k- ";
                            }

                          delete $want{$k};
                        };
                      foreach my $k (keys %want)
                        {
                          my $v = $want{$k};
                          print "$k=$v ";
                        }' "$target" "$cur"`
}

install () {
  local target="${TMPDIR}/$$"

  test -z "$1" && {
      echo "error: install: takes an argument (hint: try '$id list')" 1>&2
      exit 1;
  }
  fetch_snapshot "$1" "$target"
  shift

  apt-get "$@" install $( perl -lane 'print "$F[0]=$F[1]"' $target )

}

list () {
  case "$1" in
    ?*)
      ssh "$1" -- apt-snapshot list
      ;;
    *)
      for x in "${APT_SNAPSHOT_DIR}"/*
        do
          if test -f "$x"
            then
              printf "%s\t%s\n"                                                   \
                     "$( basename "$x" )"                                         \
                     "$( perl -e '@a=stat ($ARGV[0]);
                                print scalar localtime ($a[10])' "$x" )"
            fi
        done
      ;;
  esac
}

#---------------------------------------------------------------------
#                                Main
#---------------------------------------------------------------------

case "$1" in
  create)
    create "${2-snapshot.`date -Iseconds -u`}" #iso-8601 style date in UTC
    #create "${2-snapshot.`date +%FT%T`}"
    ;;
  restore)
    shift
    restore "$@"
    ;;
  install)
    shift
    install "$@"
    ;;
  fetch)
    shift
    fetch "$@"
    ;;
  list)
    shift
    list "$@"
    ;;
  *)
    echo "usage: $id create [ snapshot ]" 1>&2
    echo "       $id restore snapshot" 1>&2
    echo "       $id install snapshot" 1>&2
    echo "       $id list [ user@host ]" 1>&2
    echo "  where" 1>&2
    echo "    snapshot = filename or user@host:filename " 1>&2
    echo "" 1>&2
    echo "  environment variables TMPDIR and APT_SNAPSHOT_DIR influence behaviour" 1>&2
    exit 1
    ;;
esac
