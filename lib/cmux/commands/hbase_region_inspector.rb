module CMUX
  module Commands
    # Run hbase-region-inspector
    class HBaseRegionInspector
      extend Commands

      # Command properties
      CMD   = 'hbase-region-inspector'.freeze
      ALIAS = 'hri'.freeze
      DESC  = 'Run hbase-region-inspector.'.freeze

      # Regist command
      reg_cmd(cmd: CMD, alias: ALIAS, desc: DESC)

      # Initialize
      def initialize(*)
        @opt = build_opts
        @hri_port = HRI_PORT
      end

      # Run command
      def process
        Utils.do_if_sync(@opt[:sync])
        clusters = select_clusters(CM.hosts)
        run_hri(clusters)
      end

      private

      LABEL = %I[cm cl_disp cdh_ver cl].freeze

      # Select cluster(s) to run 'hbase-region-inspector'
      def select_clusters(hosts)
        title  = "Select cluster(s) to run hbase-region-inspector:\n".red
        table  = build_cluster_table(hosts)
        fzfopt = "-n1,2 --with-nth=..-2 #{@opt[:query]} --header='#{title}'"

        selected = Utils.fzf(list: table, opt: fzfopt)
        Utils.exit_if_empty(selected, 'No items selected')
        selected.map(&:split)
      end

      # Build CMUX table
      def build_cluster_table(hosts)
        header = TABLE_HEADERS.values_at(*LABEL)
        body   = hosts.select { |h| h[:role_stypes].include?('HM(A)') }
                      .map { |h| h.values_at(*LABEL) }
                      .sort_by { |e| e.map(&:djust) }
        FMT.table(header: header, body: body, rjust: [2])
      end

      # Run 'hbase-region-inspector'
      def run_hri(clusters)
        cmds = clusters.map do |cluster|
          build_command([LABEL, cluster].transpose.to_h)
        end
        TmuxWindowSplitter.new(*cmds).process
      end

      # Build command
      def build_command(cluster)
        banner  = build_banner(cluster[:cl_disp], cluster[:cdh_ver])
        hri     = HRI.hri4cdh(cluster[:cdh_ver])
        opt     = build_hri_opts(cluster[:cm], cluster[:cl])
        title   = "hbase-region-inspector: #{cluster[:cl_disp]}"
        command = "#{banner} #{HRI_HOME}/#{hri} #{opt}"
        { command: command, title: title }
      end

      # Build login banner
      def build_banner(cl_disp, cdh_ver)
        msg = "[hbase-region-inspector] #{cl_disp} (CDH #{cdh_ver})\n"
        Utils.login_banner(msg)
      end

      # Build hbase-region-inspector options
      def build_hri_opts(cm, cl)
        build_hri_port_number

        zk_leader   = CM.find_zk_leader(cm, cl)
        zk          = zk_leader[:hostname]
        zk_port     = CM.zk_port(cm, cl, zk_leader)
        krb_enabled = CM.hbase_kerberos_enabled?(cm, cl)
        krb_opt     = zk
        krb_opt     = HRI.gen_krb_opt(cm, zk, zk_port) if krb_enabled

        "--admin #{krb_opt} #{@hri_port} #{@opt[:interval]}"
      end

      # Build a port number of hbase-region-inspector.
      def build_hri_port_number
        @hri_port += 1
        @hri_port += 1 while CHK.port_open?(nil, @hri_port, 1)
      end

      # Build command options
      def build_opts
        opt = CHK::OptParser.new
        opt.banner(CMD, ALIAS)
        opt.separator('Options:')
        opt.sync_option
        opt.query_option
        opt.interval_option
        opt.help_option
        opt.parse
      end
    end
  end
end
