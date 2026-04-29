from unittest.mock import patch
from ipt_server import main as ipt_main


def test_dns_dnat_template_renders_with_backend_ip():
    rendered = ipt_main._render_dns_dnat_ruleset("10.0.0.5")
    assert "dnat to 10.0.0.5:1053" in rendered
    assert "ip daddr 10.0.0.5 udp dport 1053 masquerade" in rendered
    assert rendered.strip().startswith("table inet dns_dnat_ipt_server")


def test_border_template_empty_when_no_border():
    with patch.object(ipt_main.state, "CONFIG") as cfg:
        cfg.has_border = False
        assert ipt_main.render_border_rules() == ""


def test_border_template_includes_private_returns_when_has_border():
    with patch.object(ipt_main.state, "CONFIG") as cfg:
        cfg.has_border = True
        rendered = ipt_main.render_border_rules()
    assert "table inet border_ipt_server" in rendered
    for net in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"):
        assert f"ip daddr {net} return" in rendered
    assert 'oifname "border" masquerade' in rendered
