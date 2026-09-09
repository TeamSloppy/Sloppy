FROM node:20-alpine
WORKDIR /dashboard
COPY Dashboard/package.json Dashboard/package-lock.json* ./
RUN npm install
COPY Dashboard .
# Keep the export prompt shared with the bundled Sloppy skill.
COPY Sources/sloppy/Resources/Skills/memory-import/references/export-prompt.md /Sources/sloppy/Resources/Skills/memory-import/references/export-prompt.md
EXPOSE 25102
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0", "--port", "25102"]
