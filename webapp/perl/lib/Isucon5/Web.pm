package Isucon5::Web;
use 5.020;

use warnings;
use utf8;
use Kossy;
use DBIx::Sunny;
use Encode;
use Redis::Fast;
use Redis::LeaderBoard;
use HTTP::Date qw/str2time time2iso/;
use JSON::XS;
use Time::Piece;

sub db {
    state $db = do {
        my %db = (
            host => $ENV{ISUCON5_DB_HOST} || 'localhost',
            port => $ENV{ISUCON5_DB_PORT} || 3306,
            username => $ENV{ISUCON5_DB_USER} || 'root',
            password => $ENV{ISUCON5_DB_PASSWORD},
            database => $ENV{ISUCON5_DB_NAME} || 'isucon5q',
        );
        DBIx::Sunny->connect(
            "dbi:mysql:database=$db{database};host=$db{host};port=$db{port}", $db{username}, $db{password}, {
                RaiseError => 1,
                PrintError => 0,
                AutoInactiveDestroy => 1,
                mysql_enable_utf8   => 1,
                mysql_auto_reconnect => 1,
            },
        );
    };
}

sub redis {
    state $redis = Redis::Fast->new;
}

sub get_fp_leader_board {
    my $user_id = shift;

    Redis::LeaderBoard->new(
        redis => redis(),
        key   => 'fp_leader_board:' . $user_id,
        order => 'desc',
    );
}

sub json {
    state $json = JSON::XS->new->utf8;
}

my ($SELF, $C);
sub session {
    $C->stash->{session};
}

sub stash {
    $C->stash;
}

sub redirect {
    $C->redirect(@_);
}

sub abort_authentication_error {
    session()->{user_id} = undef;
    $C->halt(401, encode_utf8($C->tx->render('login.tx', { message => 'ログインに失敗しました' })));
}

sub abort_permission_denied {
    $C->halt(403, encode_utf8($C->tx->render('error.tx', { message => '友人のみしかアクセスできません' })));
}

sub abort_content_not_found {
    $C->halt(404, encode_utf8($C->tx->render('error.tx', { message => '要求されたコンテンツは存在しません' })));
}

sub authenticate {
    my ($email, $password) = @_;
    my $query = <<SQL;
SELECT u.id AS id, u.account_name AS account_name, u.nick_name AS nick_name, u.email AS email
FROM users u
JOIN salts s ON u.id = s.user_id
WHERE u.email = ? AND u.passhash = SHA2(CONCAT(?, s.salt), 512)
SQL
    my $result = db->select_row($query, $email, $password);
    if (!$result) {
        abort_authentication_error();
    }
    session()->{user_id} = $result->{id};
    return $result;
}

sub current_user {
    my ($self, $c) = @_;
    my $user = stash()->{user};

    return $user if ($user);

    return undef if (!session()->{user_id});

    $user = db->select_row('SELECT id, account_name, nick_name, email FROM users WHERE id=?', session()->{user_id});
    if (!$user) {
        session()->{user_id} = undef;
        abort_authentication_error();
    }
    return $user;
}

sub get_user {
    my ($user_id) = @_;
    my $user = db->select_row('SELECT * FROM users WHERE id = ?', $user_id);
    abort_content_not_found() if (!$user);
    return $user;
}

sub user_from_account {
    my ($account_name) = @_;
    my $user = db->select_row('SELECT * FROM users WHERE account_name = ?', $account_name);
    abort_content_not_found() if (!$user);
    return $user;
}

sub is_friend {
    my ($another_id) = @_;
    my $user_id = session()->{user_id};
    my $query = 'SELECT COUNT(1) AS cnt FROM relations WHERE (one = ? AND another = ?)';
    my $cnt = db->select_one($query, $user_id, $another_id, $another_id, $user_id);
    return $cnt > 0 ? 1 : 0;
}

sub is_friend_account {
    my ($account_name) = @_;
    is_friend(user_from_account($account_name)->{id});
}

state $today_str = do {
    my ($t, undef) = split(/ /, time2iso());
    $t;
};
sub mark_footprint {
    my ($owner_id) = @_;
    if ($owner_id != current_user()->{id}) {
        my $lb = get_fp_leader_board($owner_id);
        my $key = current_user()->{id} . ':::' . $today_str;
        $lb->set_score($key => time());
    }
}

sub permitted {
    my ($another_id) = @_;
    $another_id == current_user()->{id} || is_friend($another_id);
}

my $PREFS;
sub prefectures {
    $PREFS ||= do {
        [
        '未入力',
        '北海道', '青森県', '岩手県', '宮城県', '秋田県', '山形県', '福島県', '茨城県', '栃木県', '群馬県', '埼玉県', '千葉県', '東京都', '神奈川県', '新潟県', '富山県',
        '石川県', '福井県', '山梨県', '長野県', '岐阜県', '静岡県', '愛知県', '三重県', '滋賀県', '京都府', '大阪府', '兵庫県', '奈良県', '和歌山県', '鳥取県', '島根県',
        '岡山県', '広島県', '山口県', '徳島県', '香川県', '愛媛県', '高知県', '福岡県', '佐賀県', '長崎県', '熊本県', '大分県', '宮崎県', '鹿児島県', '沖縄県'
        ]
    };
}

filter 'authenticated' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        if (!current_user()) {
            return redirect('/login');
        }
        $app->($self, $c);
    }
};

filter 'set_global' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        $SELF = $self;
        $C = $c;
        $C->stash->{session} = $c->req->env->{"psgix.session"};
        $app->($self, $c);
    }
};

get '/login' => sub {
    my ($self, $c) = @_;
    $c->render('login.tx', { message => '高負荷に耐えられるSNSコミュニティサイトへようこそ!' });
};

post '/login' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    my $email = $c->req->param("email");
    my $password = $c->req->param("password");
    authenticate($email, $password);
    redirect('/');
};

get '/logout' => [qw(set_global)] => sub {
    my ($self, $c) = @_;
    session()->{user_id} = undef;
    redirect('/login');
};

get '/' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;

    my $profile = db->select_row('SELECT * FROM profiles WHERE user_id = ?', current_user()->{id});

    my $entries_query = 'SELECT id, user_id, private, title, created_at FROM entries WHERE user_id = ? ORDER BY created_at LIMIT 5';
    my $entries = [];
    for my $entry (@{db->select_all($entries_query, current_user()->{id})}) {
        $entry->{is_private} = ($entry->{private} == 1);
        push @$entries, $entry;
    }

    my $comments_for_me = [
        map {
            json()->decode($_)
        } redis()->lrange('comments_for_me:' . current_user()->{id}, 0, 9),
    ];

    my $entries_of_friends = [];
    for my $entry (@{db->select_all('SELECT e.id, e.user_id, e.private, e.title, e.created_at FROM entries e JOIN relations r ON e.user_id = r.another WHERE r.one = ? ORDER BY e.id DESC limit 10')}) {
        my $owner = get_user($entry->{user_id});
        $entry->{account_name} = $owner->{account_name};
        $entry->{nick_name} = $owner->{nick_name};
        push @$entries_of_friends, $entry;
    }

    my $current_user = current_user();
    my $comments_of_friends = [];
    for my $comment (@{ db->select_all('
            SELECT c.*
            FROM
              comments c
             JOIN
              relations r
             ON c.user_id = r.another
            WHERE
             r.one = ?
            ORDER BY c.id DESC
            limit 10
        ', $current_user->{id} ) }
    ) {
        my $entry = db->select_row('SELECT id, user_id, private FROM entries WHERE id = ?',
            $comment->{entry_id});
        $entry->{is_private} = ($entry->{private} == 1);
        my $entry_owner = get_user($entry->{user_id});
        $entry->{account_name} = $entry_owner->{account_name};
        $entry->{nick_name} = $entry_owner->{nick_name};
        $comment->{entry} = $entry;
        my $comment_owner = get_user($comment->{user_id});
        $comment->{account_name} = $comment_owner->{account_name};
        $comment->{nick_name} = $comment_owner->{nick_name};
        push @$comments_of_friends, $comment;
    }

    my $friends_query = 'SELECT * FROM relations WHERE one = ? ORDER BY id DESC';
    my %friends = ();
    my $friends = [];
    for my $rel (@{db->select_all($friends_query, $current_user->{id})}) {
        $friends{$rel->{another}} ||= do {
            my $friend = get_user($rel->{another});
            $rel->{account_name} = $friend->{account_name};
            $rel->{nick_name} = $friend->{nick_name};
            push @$friends, $rel;
            $rel;
        };
    }

    my $footprints = get_footprints(current_user()->{id}, 10);

    my $locals = {
        'user' => current_user(),
        'profile' => $profile,
        'entries' => $entries,
        'comments_for_me' => $comments_for_me,
        'entries_of_friends' => $entries_of_friends,
        'comments_of_friends' => $comments_of_friends,
        'friends' => $friends,
        'footprints' => $footprints
    };
    $c->render('index.tx', $locals);
};

sub get_footprints {
    my ($user_id, $limit) = @_;

    my $lb = get_fp_leader_board($user_id);
    my $members_and_scores = $lb->redis->zrevrange($lb->key, 0, $limit - 1, 'WITHSCORES');

    return [] unless @$members_and_scores;

    my %owners;
    my $footprints;
    while (my ($owner_id, $epoch) = splice @$members_and_scores, 0, 2) {
        ($owner_id, my $date) = split /:::/, $owner_id;
        $owners{$owner_id} = 1;

        my $fp = {
            user_id  => $user_id,
            owner_id => $owner_id,
            date     => $date,
            updated  => time2iso($epoch),
        };
        push @$footprints, $fp;
    }

    my @owner_ids = sort {$a <=> $b} keys %owners;
    my %owner_hash;
    for my $owner ( @{db->select_all('SELECT * FROM users WHERE id IN (?)', \@owner_ids)} ) {
        $owner_hash{$owner->{id}} = $owner;
    }

    for my $fp (@$footprints) {
        my $owner = $owner_hash{$fp->{owner_id}};
        $fp->{account_name} = $owner->{account_name};
        $fp->{nick_name}    = $owner->{nick_name};
    }
    $footprints;
}

get '/profile/:account_name' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $account_name = $c->args->{account_name};
    my $owner = user_from_account($account_name);
    my $prof = db->select_row('SELECT * FROM profiles WHERE user_id = ?', $owner->{id});
    $prof = {} if (!$prof);
    my $query;
    if (permitted($owner->{id})) {
        $query = 'SELECT * FROM entries WHERE user_id = ? ORDER BY created_at LIMIT 5';
    } else {
        $query = 'SELECT * FROM entries WHERE user_id = ? AND private=0 ORDER BY created_at LIMIT 5';
    }
    my $entries = [];
    for my $entry (@{db->select_all($query, $owner->{id})}) {
        $entry->{is_private} = ($entry->{private} == 1);
        my ($title, $content) = split(/\n/, $entry->{body}, 2);
        $entry->{title} = $title;
        $entry->{content} = $content;
        push @$entries, $entry;
    }
    mark_footprint($owner->{id});
    my $locals = {
        owner => $owner,
        profile => $prof,
        entries => $entries,
        private => permitted($owner->{id}),
        is_friend => is_friend($owner->{id}),
        current_user => current_user(),
        prefectures => prefectures(),
    };
    $c->render('profile.tx', $locals);
};

post '/profile/:account_name' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $account_name = $c->args->{account_name};
    if ($account_name != current_user()->{account_name}) {
        abort_permission_denied();
    }
    my $first_name =  $c->req->param('first_name');
    my $last_name = $c->req->param('last_name');
    my $sex = $c->req->param('sex');
    my $birthday = $c->req->param('birthday');
    my $pref = $c->req->param('pref');

    my $prof = db->select_row('SELECT * FROM profiles WHERE user_id = ?', current_user()->{id});
    if ($prof) {
      my $query = <<SQL;
UPDATE profiles
SET first_name=?, last_name=?, sex=?, birthday=?, pref=?, updated_at=CURRENT_TIMESTAMP()
WHERE user_id = ?
SQL
        db->query($query, $first_name, $last_name, $sex, $birthday, $pref, current_user()->{id});
    } else {
        my $query = <<SQL;
INSERT INTO profiles (user_id,first_name,last_name,sex,birthday,pref) VALUES (?,?,?,?,?,?)
SQL
        db->query($query, current_user()->{id}, $first_name, $last_name, $sex, $birthday, $pref);
    }
    redirect('/profile/'.$account_name);
};

get '/diary/entries/:account_name' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $account_name = $c->args->{account_name};
    my $owner = user_from_account($account_name);
    my $query;
    if (permitted($owner->{id})) {
        $query = 'SELECT * FROM entries WHERE user_id = ? ORDER BY created_at DESC LIMIT 20';
    } else {
        $query = 'SELECT * FROM entries WHERE user_id = ? AND private=0 ORDER BY created_at DESC LIMIT 20';
    }
    my $entries = [];
    for my $entry (@{db->select_all($query, $owner->{id})}) {
        $entry->{is_private} = ($entry->{private} == 1);
        my ($title, $content) = split(/\n/, $entry->{body}, 2);
        $entry->{title} = $title;
        $entry->{content} = $content;
        $entry->{comment_count} = db->select_one('SELECT COUNT(*) AS c FROM comments WHERE entry_id = ?', $entry->{id});
        push @$entries, $entry;
    }
    mark_footprint($owner->{id});
    my $locals = {
        owner => $owner,
        entries => $entries,
        myself => (current_user()->{id} == $owner->{id}),
    };
    $c->render('entries.tx', $locals);
};

get '/diary/entry/:entry_id' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $entry_id = $c->args->{entry_id};
    my $entry = db->select_row('SELECT * FROM entries WHERE id = ?', $entry_id);
    abort_content_not_found() if (!$entry);
    my ($title, $content) = split(/\n/, $entry->{body}, 2);
    $entry->{title} = $title;
    $entry->{content} = $content;
    $entry->{is_private} = ($entry->{private} == 1);
    my $owner = get_user($entry->{user_id});
    if ($entry->{is_private} && !permitted($owner->{id})) {
        abort_permission_denied();
    }
    my $comments = [];
    for my $comment (@{db->select_all('SELECT * FROM comments WHERE entry_id = ?', $entry->{id})}) {
        my $comment_user = get_user($comment->{user_id});
        $comment->{account_name} = $comment_user->{account_name};
        $comment->{nick_name} = $comment_user->{nick_name};
        push @$comments, $comment;
    }
    mark_footprint($owner->{id});
    my $locals = {
        'owner' => $owner,
        'entry' => $entry,
        'comments' => $comments,
    };
    $c->render('entry.tx', $locals);
};

post '/diary/entry' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $query = 'INSERT INTO entries (user_id, private, body, title) VALUES (?,?,?,?)';
    my $title = $c->req->param('title');
    my $content = $c->req->param('content');
    my $private = $c->req->param('private');
    my $body = ($title || "タイトルなし") . "\n" . $content;
    db->query($query, current_user()->{id}, ($private ? '1' : '0'), $body, ($title || "タイトルなし"));
    redirect('/diary/entries/'.current_user()->{account_name});
};

post '/diary/comment/:entry_id' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $entry_id = $c->args->{entry_id};
    my $entry = db->select_row('SELECT * FROM entries WHERE id = ?', $entry_id);
    abort_content_not_found() if (!$entry);
    $entry->{is_private} = ($entry->{private} == 1);
    if ($entry->{is_private} && !permitted($entry->{user_id})) {
        abort_permission_denied();
    }
    my $query = 'INSERT INTO comments (entry_id, user_id, comment) VALUES (?,?,?)';
    my $comment = $c->req->param('comment');
    db->query($query, $entry->{id}, current_user()->{id}, $comment);
    # update comments_for_me cache
    my $redis_key = 'comments_for_me:' . $entry->{user_id};
    my $now = Time::Piece->localtime;
    my $data = +{
        entry_id => $entry->{id},
        user_id => current_user()->{id},
        comment => $comment,
        created_at => join(' ', $now->ymd, $now->hms),
        account_name => current_user()->{account_name},
        nick_name => current_user()->{nick_name},
    };
    redis()->lpush($redis_key, json()->encode($data));
    redis()->ltrim($redis_key, 0, 9);

    redirect('/diary/entry/'.$entry->{id});
};

get '/footprints' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;

    my $footprints = get_footprints(current_user()->{id}, 50);
    $c->render('footprints.tx', { footprints => $footprints });
};

get '/friends' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $query = 'SELECT * FROM relations WHERE one = ? ORDER BY id DESC';
    my %friends = ();
    my $friends = [];
    for my $rel (@{db->select_all($query, current_user()->{id})}) {
        $friends{$rel->{another}} ||= do {
            my $friend = get_user($rel->{another});
            $rel->{account_name} = $friend->{account_name};
            $rel->{nick_name} = $friend->{nick_name};
            push @$friends, $rel;
            $rel;
        };
    }
    $c->render('friends.tx', { friends => $friends });
};

post '/friends/:account_name' => [qw(set_global authenticated)] => sub {
    my ($self, $c) = @_;
    my $account_name = $c->args->{account_name};
    if (!is_friend_account($account_name)) {
        my $user = user_from_account($account_name);
        abort_content_not_found() if (!$user);
        db->query('INSERT INTO relations (one, another) VALUES (?,?), (?,?)', current_user()->{id}, $user->{id}, $user->{id}, current_user()->{id});
        redirect('/friends');
    }
};

get '/initialize' => sub {
    my ($self, $c) = @_;
    db->query("DELETE FROM relations WHERE id > 500000");
    db->query("DELETE FROM footprints WHERE id > 500000");
    db->query("DELETE FROM entries WHERE id > 500000");
    db->query("DELETE FROM comments WHERE id > 1500000");

    if ($c->req->param('redis')) {
        initialize_fp_score_board();
        # cache comments_for_me
        for my $user_id (1 .. 5000) {
            my $key = 'comments_for_me:' . $user_id;
            redis()->del($key);

            my $comments_for_me_query = <<SQL;
                SELECT c.entry_id AS entry_id, c.user_id AS user_id, c.comment AS comment, c.created_at AS created_at, u.account_name AS account_name, u.nick_name AS nick_name
                FROM comments c
                JOIN entries e ON c.entry_id = e.id
                JOIN users u ON c.user_id = u.id
                WHERE e.user_id = ?
                ORDER BY c.created_at DESC
                LIMIT 10
SQL
            for my $comment (@{db->select_all($comments_for_me_query, $user_id)}) {
                redis()->lpush($key, json()->encode($comment));
                redis()->ltrim($key, 0, 9);
            }
        }
    }
    1;
};

sub initialize_fp_score_board {
    my $query = '
        SELECT user_id, owner_id, DATE(created_at) AS date, MAX(created_at) as updated
        FROM footprints
        WHERE footprints.id <= 500000
        GROUP BY user_id, owner_id, DATE(created_at)
        ORDER BY updated DESC
    ';
    for my $fp (@{db->select_all($query)}) {
        my $lb = get_fp_leader_board($fp->{owner_id});
        my $key = sprintf "%s:::%s", $fp->{user_id}, $fp->{date};
        $lb->set_score($key => str2time($fp->{updated}));
    }
}

1;
