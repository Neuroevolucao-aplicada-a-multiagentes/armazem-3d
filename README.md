# armazem-3d

Armazém tridimensional em Godot 4.6 com oito robôs controlados pela mesma rede neural, sem comunicação entre si. A rede foi treinada por neuroevolução no repositório [treinamento-neuroevolutivo](https://github.com/Neuroevolucao-aplicada-a-multiagentes/treinamento-neuroevolutivo), e seus pesos ficam em `assets/melhor_rede_fase5.json`.

Duas camadas externas à rede completam a operação: a de recuperação, que faz o robô preso em contato com um obstáculo deslizar ao longo dele, e a de reatribuição, que troca a coleta de quem passa 8 segundos sem se aproximar do alvo.

Faz parte do TCC *Neuroevolução aplicada à simulação de multiagentes em ambientes logísticos* (Instituto Mauá de Tecnologia, 2026).

## Como executar

Abra a pasta no Godot 4.6 e execute a cena principal (F5).

| Tecla | Ação |
|---|---|
| R | Zera a contagem do painel |
| H | Mostra ou oculta o painel |
| C | Liga ou desliga a câmera automática |
| F11 | Alterna tela cheia |

Opções de linha de comando, depois de `--`:

| Opção | Efeito |
|---|---|
| `--robos=N` | Número de robôs (padrão 8) |
| `--semente=N` | Semente do sorteio das vagas |
| `--pausa=N` | Parada ao coletar, em milissegundos |
| `--folga_alvo=N` | Distância entre a prateleira e o alvo de coleta, em décimos de unidade |
| `--medir=S` | Imprime o desempenho de cada robô após S segundos e encerra |
| `--sem-reatribuicao` | Desliga a camada de reatribuição |
| `--sem-desencalhe` | Desliga a camada de recuperação |

## Atualizar os pesos

No repositório de treino:

```
python src/exportar_pesos_godot.py --fase 5
```

## Teste de paridade

Confere que a implementação em GDScript reproduz a do Python a partir de `assets/golden_vectors.json`:

```
godot --headless --path . res://teste_paridade.tscn
```

## Repositórios do projeto

- [treinamento-neuroevolutivo](https://github.com/Neuroevolucao-aplicada-a-multiagentes/treinamento-neuroevolutivo): treino da rede por algoritmo genético
- [armazem-2d](https://github.com/Neuroevolucao-aplicada-a-multiagentes/armazem-2d): armazém bidimensional em Pygame
- **armazem-3d** (este)
- [dashboard-analitico](https://github.com/Neuroevolucao-aplicada-a-multiagentes/dashboard-analitico): painel de resultados em Streamlit
