"""Пушит одну значимую сводку сессии в Cognee L4 (add + cognify).
Вызывается из SessionEnd-хука (async). Балансный режим: 1 cognify за сессию."""
import asyncio
import sys
import cognee


async def main(text: str):
    text = (text or "").strip()
    if len(text) < 20:
        return
    await cognee.add(text)
    await cognee.cognify()


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
    asyncio.run(main(arg))
