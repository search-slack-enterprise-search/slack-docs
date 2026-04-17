# Enterprise SearchのAWS Lambda動作可否

## 知りたいこと

Enterprise SearchをAWS Lambdaで動かせるか

## 目的

Enterprise Searchの実装において動作環境としてAWS Lambdaを使えるのか知りたい。Event Subscriptionの仕組みを使う場合ならhook先のURLを指定できるとのことだったのでできるとはおもうのですが。

## 調査サマリー

### 結論: AWS Lambda で Enterprise Search は動かせる（YES）

Enterprise Search は Event Subscriptions（HTTP エンドポイント）を使う。Request URL に API Gateway や Lambda Function URL を指定すれば Lambda で受信できる。

### カスタムエージェントとの重要な違い

| 項目 | カスタムエージェント | Enterprise Search |
|------|---------------------|-------------------|
| ACK タイムアウト | 3秒 | **10秒** |
| 処理方式 | 非同期（Lazy listener） | **同期（10秒以内に complete()）** |
| Lazy listener | 必要 | **不要** |

Enterprise Search は 10 秒以内に同期完了させる設計なので、Lambda での Lazy listener パターンは不要。

### Bolt for Python + Lambda の実装ポイント

```python
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler

app = App(
    process_before_response=True,  # FaaS 環境で必須
    signing_secret=os.environ["SLACK_SIGNING_SECRET"],
    token=os.environ["SLACK_BOT_TOKEN"],
)

@app.function("search_function", auto_acknowledge=False, ack_timeout=10)
def handle_search(ack, complete, fail, inputs):
    try:
        results = search_external_data(inputs["query"], inputs.get("filters", {}))
        complete(outputs={"search_results": results})
    except Exception as e:
        fail(error=str(e))
    finally:
        ack()  # complete()/fail() の後に呼ぶ

def lambda_handler(event, context):
    return SlackRequestHandler(app=app).handle(event, context)
```

- `auto_acknowledge=False`: ack() の呼び出しタイミングを手動制御
- `ack_timeout=10`: デフォルト 3 秒を Enterprise Search の上限 10 秒に延長
- Lambda タイムアウト設定は **15〜30 秒**推奨

### IAM 権限

Enterprise Search のみであれば Lazy listener 不要のため、Lambda 自己invoke権限（`lambda:InvokeFunction`）は不要。外部データソース（DynamoDB など）へのアクセス権限のみ付与すれば良い。

## 完了サマリー

Enterprise SearchをAWS Lambdaで動かすことは可能と確認した。

Event Subscriptionsの Request URL にAPI GatewayやLambda Function URLを指定することで、Slackからのイベントを受信できる。カスタムエージェントと異なり、Enterprise Searchは「10秒以内に同期完了」という設計のため Lazy listener は不要。Bolt for Python では `auto_acknowledge=False, ack_timeout=10` の設定と `process_before_response=True` の組み合わせで実現する。Lambda のタイムアウトは15〜30秒に設定することを推奨。
