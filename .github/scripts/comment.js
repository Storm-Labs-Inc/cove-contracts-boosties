module.exports = async ({ github, context, header, body }) => {
  let comment = [header, body].join("\n");

  const collapseMarkdown = `
<details>
  <summary>Expand Summary</summary>
`;

  comment = comment.replace('##', `${insertText}\n##`);
  comment += '\n</details>';

  const { data: comments } = await github.rest.issues.listComments({
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.payload.number,
  });

  const botComment = comments.find(
    (comment) =>
      // github-actions bot user
      comment.user.id === 41898282 && comment.body.startsWith(header)
  );

  const commentFn = botComment ? "updateComment" : "createComment";

  await github.rest.issues[commentFn]({
    owner: context.repo.owner,
    repo: context.repo.repo,
    body: comment,
    ...(botComment
      ? { comment_id: botComment.id }
      : { issue_number: context.payload.number }),
  });
};
