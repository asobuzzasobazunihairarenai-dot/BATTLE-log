// Supabase Edge Function: notify-on-event
// 役割: matches / game_comments / players テーブルに新しい行が INSERT されたとき、
//       管理者設定(app_settings)のON/OFFに従って asobuzz.asobazunihairarenai@gmail.com にメール通知する。
//
// デプロイ方法(Supabaseダッシュボード):
//   1. 左メニュー「Edge Functions」→「Deploy a new function」
//   2. Function name: notify-on-event
//   3. このファイルの中身をまるごと貼り付けて Deploy
//
// 必要なSecrets(Edge Functions > notify-on-event > Settings > Secrets、または
//   Project Settings > Edge Functions > Secrets で設定):
//   - RESEND_API_KEY   … Resendダッシュボードで発行したAPIキー
//   - WEBHOOK_SECRET    … 好きな英数字の文字列(合言葉)。Database Webhook側にも同じ値を設定する
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY は Supabase が自動で環境変数として渡してくれるので、
// 自分で設定する必要はありません。

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const NOTIFY_TO = 'asobuzz.asobazunihairarenai@gmail.com'

Deno.serve(async (req) => {
  try {
    // Database Webhook側で設定した合言葉ヘッダーと一致するかチェック(なりすまし防止)
    if (req.headers.get('x-webhook-secret') !== WEBHOOK_SECRET) {
      return new Response('unauthorized', { status: 401 })
    }

    const payload = await req.json()
    const table = payload.table
    const record = payload.record

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
    const { data: settings } = await supabase
      .from('app_settings')
      .select('notify_on_match, notify_on_comment, notify_on_player')
      .eq('id', 1)
      .maybeSingle()

    let shouldNotify = false
    let subject = ''
    let bodyLines: string[] = []

    if (table === 'matches' && record.status === 'pending' && settings?.notify_on_match) {
      shouldNotify = true
      subject = '【7 SHADES OF S:EVEN】新しい戦績申請があります'
      bodyLines = [
        `日付: ${record.date}`,
        `参加メンバー数: ${(record.members || []).length}人`,
        `プレイ時間: ${record.duration_minutes ? record.duration_minutes + '分' : '未入力'}`,
        '',
        '管理者コンソールから承認をお願いします。'
      ]
    } else if (table === 'game_comments' && settings?.notify_on_comment) {
      shouldNotify = true
      subject = '【7 SHADES OF S:EVEN】新しいコメントがあります'
      bodyLines = [
        `コメント: ${record.comment}`
      ]
    } else if (table === 'players' && record.status === 'pending' && settings?.notify_on_player) {
      shouldNotify = true
      subject = '【7 SHADES OF S:EVEN】新しいプレイヤー登録申請があります'
      bodyLines = [
        `名前: ${record.name}`,
        '',
        '管理者コンソールから承認をお願いします。'
      ]
    }

    if (!shouldNotify) {
      return new Response(JSON.stringify({ skipped: true }), { status: 200 })
    }

    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: 'onboarding@resend.dev',
        to: NOTIFY_TO,
        subject: subject,
        text: bodyLines.join('\n')
      })
    })

    const result = await emailRes.json()
    return new Response(JSON.stringify({ sent: emailRes.ok, result }), { status: 200 })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 })
  }
})
