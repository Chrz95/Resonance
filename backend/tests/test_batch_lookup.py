import httpx
import pytest
from app.providers import Providers


@pytest.mark.asyncio
@pytest.mark.parametrize('configured', [False, True])
async def test_batch_lookup_configuration_status(monkeypatch, tmp_path, configured):
    for name in ('ALL_PROXY', 'all_proxy', 'HTTP_PROXY', 'http_proxy', 'HTTPS_PROXY', 'https_proxy'):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv('ACOUSTID_API_KEY', 'test-key' if configured else '')
    provider = Providers()
    calls = []

    async def fingerprint(path):
        return 'AQAA-generated-fingerprint'

    monkeypatch.setattr(provider, 'fingerprint', fingerprint)
    provider.key = 'test-key' if configured else ''
    await provider.client.aclose()
    provider.client = httpx.AsyncClient(transport=httpx.MockTransport(
        lambda request: calls.append(request) or httpx.Response(200, json={'status': 'ok', 'results': []})))
    try:
        result = await provider.identify(tmp_path / 'source.mp3', 180)
        assert result['lookup_performed'] is configured
        assert len(result['signature']) == 64
        assert result['candidates'] == []
        assert len(calls) == int(configured)
    finally:
        await provider.close()
