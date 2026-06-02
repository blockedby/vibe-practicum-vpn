package ikev2

import "github.com/kcnc/vibe-practicum-vpn/internal/config"

type Effective struct {
	Configured bool
	config.IKEv2Config
}

func EffectiveConfig(c *config.IKEv2Config) Effective {
	eff := Effective{IKEv2Config: config.DefaultIKEv2Config()}
	if c == nil {
		return eff
	}
	eff.Configured = true
	eff.IKEv2Config = *c
	eff.IKEv2Config.ApplyDefaults()
	return eff
}
