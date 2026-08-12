"""Servidor local para testar o export web (Etapa 9).

Por que nao serve `python -m http.server`: o preset Web usa suporte a threads, e o
navegador so libera SharedArrayBuffer quando a pagina vem com os dois cabecalhos de
isolamento de origem abaixo. Sem eles a tela fica preta e o console reclama de
SharedArrayBuffer -- que parece defeito do jogo e nao e.

O itch.io manda esses mesmos cabecalhos quando a opcao "SharedArrayBuffer support" esta
marcada no projeto. Este script existe so para conferir o build ANTES de subir.

Uso:
    godot --headless --path . --export-release "Web" build/web/index.html
    python tools/servir_web.py            # abre em http://localhost:8060
"""

from __future__ import annotations

import functools
import http.server
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTA = os.path.join(RAIZ, "build", "web")
PORTA = int(sys.argv[1]) if len(sys.argv) > 1 else 8060


class Isolado(http.server.SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # O .wasm precisa do tipo certo para o navegador compila-lo em streaming.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, formato: str, *args) -> None:
        sys.stderr.write("  %s\n" % (formato % args))

    def handle_one_request(self) -> None:
        # O navegador deixa conexoes abertas e as derruba sem avisar -- ao fechar a aba, ao
        # recarregar, ao trocar de pagina. No Windows isso chega como ConnectionResetError
        # (WinError 10054), e sem este try o servidor despeja um traceback e MORRE no meio
        # do teste: a proxima recarga da pagina nao responde e parece defeito do build.
        # Conexao derrubada pelo cliente nao e erro do servidor.
        try:
            super().handle_one_request()
        except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
            self.close_connection = True


def main() -> None:
    if not os.path.isfile(os.path.join(PASTA, "index.html")):
        print("Nao ha build em %s -- exporte primeiro." % PASTA)
        raise SystemExit(1)

    manipulador = functools.partial(Isolado, directory=PASTA)
    servidor = http.server.ThreadingHTTPServer(("127.0.0.1", PORTA), manipulador)
    print("servindo %s em http://localhost:%d" % (PASTA, PORTA))
    servidor.serve_forever()


if __name__ == "__main__":
    main()
