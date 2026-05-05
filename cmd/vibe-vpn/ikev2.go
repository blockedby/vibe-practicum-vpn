package main

import (
	"fmt"

	"github.com/kcnc/vibe-practicum-vpn/internal/ikev2"
	"github.com/spf13/cobra"
)

func newIKEv2Command(o *cliOptions) *cobra.Command {
	root := &cobra.Command{Use: "ikev2", Short: "Manage IKEv2/IPsec skeleton configuration", Long: "Manage IKEv2/IPsec skeleton configuration. This milestone is read-only except for future command placeholders."}

	root.AddCommand(&cobra.Command{Use: "status", Short: "Show configured IKEv2 defaults and skeleton status", RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		_, err = fmt.Fprint(cmd.OutOrStdout(), ikev2.Status(c.IKEv2))
		return err
	}})
	root.AddCommand(&cobra.Command{Use: "doctor", Short: "Validate IKEv2 config only; no system changes", RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		out, err := ikev2.Doctor(c.IKEv2)
		_, printErr := fmt.Fprint(cmd.OutOrStdout(), out)
		if printErr != nil {
			return printErr
		}
		return err
	}})

	pki := placeholderParent("pki", "Manage IKEv2 PKI")
	pki.AddCommand(&cobra.Command{Use: "init", Short: "Initialize local IKEv2 PKI/state directories", Args: cobra.NoArgs, RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		eff := ikev2.EffectiveConfig(c.IKEv2)
		if err := ikev2.InitPKI(eff.IKEv2Config); err != nil {
			return err
		}
		_, err = fmt.Fprintf(cmd.OutOrStdout(), "initialized ikev2 pki/state directories\nconfig_dir: %s\nstate_dir: %s\nsecret_material: not printed\n", eff.ConfigDir, eff.StateDir)
		return err
	}})
	root.AddCommand(pki)

	server := placeholderParent("server", "Manage strongSwan server placeholders")
	server.AddCommand(notImplemented("render", "Render strongSwan config"))
	install := notImplemented("install", "Install rendered strongSwan config")
	install.Flags().Bool("dry-run", false, "show what would be installed without changing the system")
	server.AddCommand(install)
	server.AddCommand(notImplemented("reload", "Reload strongSwan service"))
	root.AddCommand(server)

	xfrm := placeholderParent("xfrm", "Manage XFRM interface placeholders")
	xfrm.AddCommand(notImplemented("status", "Show XFRM runtime status"))
	installXFRM := notImplemented("install", "Install XFRM interface")
	installXFRM.Flags().Bool("dry-run", false, "show what would be installed without changing the system")
	xfrm.AddCommand(installXFRM)
	xfrm.AddCommand(notImplemented("disable", "Disable XFRM interface"))
	root.AddCommand(xfrm)

	routing := placeholderParent("routing", "Manage IKEv2 routing placeholders")
	routing.AddCommand(notImplemented("status", "Show IKEv2 routing status"))
	enableRouting := notImplemented("enable", "Enable IKEv2 routing")
	enableRouting.Flags().Bool("dry-run", false, "show what would be changed without changing the system")
	routing.AddCommand(enableRouting)
	routing.AddCommand(notImplemented("disable", "Disable IKEv2 routing"))
	root.AddCommand(routing)

	client := placeholderParent("client", "Manage IKEv2 clients")
	var clientIP, clientOS string
	create := &cobra.Command{Use: "create <name>", Short: "Create an IKEv2 client registry entry", Args: cobra.ExactArgs(1), RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		eff := ikev2.EffectiveConfig(c.IKEv2)
		if err := ikev2.InitPKI(eff.IKEv2Config); err != nil {
			return err
		}
		cl, err := ikev2.NewRegistry(eff.IKEv2Config).Create(args[0], clientIP, clientOS)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintf(cmd.OutOrStdout(), "created ikev2 client\nname: %s\nip: %s\nos: %s\nrevoked: %t\nsecret_material: not printed\n", cl.Name, cl.IP, cl.OS, cl.Revoked)
		return err
	}}
	create.Flags().StringVar(&clientIP, "ip", "", "client VPN IP inside configured subnet")
	create.Flags().StringVar(&clientOS, "os", "", "client OS: ios, android, windows, or linux")
	_ = create.MarkFlagRequired("ip")
	client.AddCommand(create)
	client.AddCommand(&cobra.Command{Use: "list", Short: "List IKEv2 clients", Args: cobra.NoArgs, RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		eff := ikev2.EffectiveConfig(c.IKEv2)
		clients, err := ikev2.NewRegistry(eff.IKEv2Config).List()
		if err != nil {
			return err
		}
		if len(clients) == 0 {
			_, err = fmt.Fprintln(cmd.OutOrStdout(), "no ikev2 clients registered")
			return err
		}
		for _, cl := range clients {
			if _, err := fmt.Fprintf(cmd.OutOrStdout(), "%s\t%s\t%s\trevoked=%t\n", cl.Name, cl.IP, cl.OS, cl.Revoked); err != nil {
				return err
			}
		}
		return nil
	}})
	client.AddCommand(notImplemented("render <name>", "Render an IKEv2 client profile"))
	client.AddCommand(&cobra.Command{Use: "revoke <name>", Short: "Revoke an IKEv2 client", Args: cobra.ExactArgs(1), RunE: func(cmd *cobra.Command, args []string) error {
		c, err := loadConfig(o.configPath)
		if err != nil {
			return err
		}
		eff := ikev2.EffectiveConfig(c.IKEv2)
		if err := ikev2.NewRegistry(eff.IKEv2Config).Revoke(args[0]); err != nil {
			return err
		}
		_, err = fmt.Fprintf(cmd.OutOrStdout(), "revoked ikev2 client\nname: %s\nsecret_material: not printed\n", args[0])
		return err
	}})
	client.AddCommand(notImplemented("audit <name>", "Audit an IKEv2 client"))
	root.AddCommand(client)

	return root
}

func placeholderParent(use, short string) *cobra.Command {
	return &cobra.Command{Use: use, Short: short, Run: func(cmd *cobra.Command, args []string) { _ = cmd.Help() }}
}

func notImplemented(use, short string) *cobra.Command {
	return &cobra.Command{Use: use, Short: short, RunE: func(cmd *cobra.Command, args []string) error {
		return fmt.Errorf("ikev2 %s is not implemented yet", cmd.CommandPath())
	}}
}
